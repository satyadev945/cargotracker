package org.eclipse.cargotracker.interfaces;

import java.util.Map;
import java.util.logging.Level;
import java.util.logging.Logger;
import redis.clients.jedis.DefaultJedisClientConfig;
import redis.clients.jedis.HostAndPort;
import redis.clients.jedis.Jedis;

/**
 * Lookup cache shared across replicas, backed by Azure Cache for Redis. Connection settings are
 * injected via environment variables (REDIS_HOST, REDIS_PORT, REDIS_PASSWORD, REDIS_SSL), populated
 * from Azure Key Vault through the CSI driver. When REDIS_HOST is not set (e.g. local development)
 * or Redis is unreachable, callers fall back to the supplied default values.
 */
public final class RedisLookupCache {

  private static final Logger logger = Logger.getLogger(RedisLookupCache.class.getName());

  private static final String REDIS_HOST = System.getenv("REDIS_HOST");
  private static final int REDIS_PORT =
      Integer.parseInt(System.getenv().getOrDefault("REDIS_PORT", "6380"));
  private static final String REDIS_PASSWORD = System.getenv("REDIS_PASSWORD");
  private static final boolean REDIS_SSL =
      Boolean.parseBoolean(System.getenv().getOrDefault("REDIS_SSL", "true"));

  private RedisLookupCache() {
    /* Prevent instantiation. */
  }

  public static boolean isEnabled() {
    return REDIS_HOST != null && !REDIS_HOST.isBlank();
  }

  private static Jedis newJedis() {
    DefaultJedisClientConfig.Builder config = DefaultJedisClientConfig.builder().ssl(REDIS_SSL);
    if (REDIS_PASSWORD != null && !REDIS_PASSWORD.isEmpty()) {
      config.password(REDIS_PASSWORD);
    }
    return new Jedis(new HostAndPort(REDIS_HOST, REDIS_PORT), config.build());
  }

  /** Seeds the given Redis hash with the supplied entries (no-op when Redis is not configured). */
  public static void seed(String hashKey, Map<String, String> entries) {
    if (!isEnabled() || entries.isEmpty()) {
      return;
    }
    try (Jedis jedis = newJedis()) {
      jedis.hset(hashKey, entries);
    } catch (RuntimeException e) {
      logger.log(Level.WARNING, "Unable to seed Redis cache " + hashKey, e);
    }
  }

  /**
   * Returns the value for the field, or {@code defaultValue} if Redis is off/unavailable/missing.
   */
  public static String get(String hashKey, String field, String defaultValue) {
    if (!isEnabled()) {
      return defaultValue;
    }
    try (Jedis jedis = newJedis()) {
      String value = jedis.hget(hashKey, field);
      return value != null ? value : defaultValue;
    } catch (RuntimeException e) {
      logger.log(Level.FINE, "Redis lookup failed for " + hashKey + ":" + field, e);
      return defaultValue;
    }
  }
}
