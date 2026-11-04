package org.eclipse.cargotracker.interfaces;

import static org.eclipse.cargotracker.domain.model.location.Location.UNKNOWN;
import static org.eclipse.cargotracker.domain.model.location.SampleLocations.CHICAGO;
import static org.eclipse.cargotracker.domain.model.location.SampleLocations.DALLAS;
import static org.eclipse.cargotracker.domain.model.location.SampleLocations.GOTHENBURG;
import static org.eclipse.cargotracker.domain.model.location.SampleLocations.HAMBURG;
import static org.eclipse.cargotracker.domain.model.location.SampleLocations.HANGZOU;
import static org.eclipse.cargotracker.domain.model.location.SampleLocations.HELSINKI;
import static org.eclipse.cargotracker.domain.model.location.SampleLocations.HONGKONG;
import static org.eclipse.cargotracker.domain.model.location.SampleLocations.MELBOURNE;
import static org.eclipse.cargotracker.domain.model.location.SampleLocations.NEWYORK;
import static org.eclipse.cargotracker.domain.model.location.SampleLocations.ROTTERDAM;
import static org.eclipse.cargotracker.domain.model.location.SampleLocations.SHANGHAI;
import static org.eclipse.cargotracker.domain.model.location.SampleLocations.STOCKHOLM;
import static org.eclipse.cargotracker.domain.model.location.SampleLocations.TOKYO;

import java.util.HashMap;
import java.util.Map;
import java.util.logging.Level;
import java.util.logging.Logger;
import org.eclipse.cargotracker.domain.model.location.Location;
import org.eclipse.cargotracker.domain.model.location.UnLocode;
import redis.clients.jedis.Jedis;
import redis.clients.jedis.JedisPool;

/**
 * At the moment, coordinates are produced by a simple factory. It may be converted to a repository
 * if coordinates become a domain layer concern.
 */
public class CoordinatesFactory {

  private static final Logger LOGGER = Logger.getLogger(CoordinatesFactory.class.getName());

  // Coordinates are shared across all replicas through a Redis (ElastiCache) hash. The immutable
  // defaults below are only seed data, and the fallback used when REDIS_HOST is not configured or
  // Redis is unavailable.
  private static final String REDIS_COORDINATES_KEY = "cargotracker:coordinates";
  private static final Map<String, Coordinates> DEFAULT_COORDINATES;
  private static final JedisPool JEDIS_POOL;

  private CoordinatesFactory() {
    /* Prevent instantiation. */
  }

  public static Coordinates find(Location location) {
    return find(location.getUnLocode());
  }

  public static Coordinates find(UnLocode unLocode) {
    return find(unLocode.getIdString());
  }

  public static Coordinates find(String unLocode) {
    if (JEDIS_POOL != null) {
      try (Jedis jedis = JEDIS_POOL.getResource()) {
        String value = jedis.hget(REDIS_COORDINATES_KEY, unLocode);
        if (value != null) {
          String[] parts = value.split(",");
          return new Coordinates(Double.parseDouble(parts[0]), Double.parseDouble(parts[1]));
        }
      } catch (RuntimeException e) {
        LOGGER.log(Level.WARNING, "Redis coordinates lookup failed, using defaults.", e);
      }
    }
    return DEFAULT_COORDINATES.get(unLocode);
  }

  static {
    Map<String, Coordinates> map = new HashMap<>();

    // TODO See if there is a service to get the latitude/longitude data from.
    map.put(HONGKONG.getUnLocode().getIdString(), new Coordinates(22, 114));
    map.put(MELBOURNE.getUnLocode().getIdString(), new Coordinates(-38, 145));
    map.put(STOCKHOLM.getUnLocode().getIdString(), new Coordinates(59, 18));
    map.put(HELSINKI.getUnLocode().getIdString(), new Coordinates(60, 25));
    map.put(CHICAGO.getUnLocode().getIdString(), new Coordinates(42, -88));
    map.put(TOKYO.getUnLocode().getIdString(), new Coordinates(36, 140));
    map.put(HAMBURG.getUnLocode().getIdString(), new Coordinates(54, 10));
    map.put(SHANGHAI.getUnLocode().getIdString(), new Coordinates(31, 121));
    map.put(ROTTERDAM.getUnLocode().getIdString(), new Coordinates(52, 5));
    map.put(GOTHENBURG.getUnLocode().getIdString(), new Coordinates(58, 12));
    map.put(HANGZOU.getUnLocode().getIdString(), new Coordinates(30, 120));
    map.put(NEWYORK.getUnLocode().getIdString(), new Coordinates(41, -74));
    map.put(DALLAS.getUnLocode().getIdString(), new Coordinates(33, -97));
    map.put(UNKNOWN.getUnLocode().getIdString(), new Coordinates(-90, 0)); // The South Pole.

    DEFAULT_COORDINATES = Map.copyOf(map);

    JedisPool pool = null;
    String redisHost = System.getenv("REDIS_HOST");
    if (redisHost != null && !redisHost.isBlank()) {
      try {
        int redisPort = Integer.parseInt(System.getenv().getOrDefault("REDIS_PORT", "6379"));
        pool = new JedisPool(redisHost, redisPort);
        try (Jedis jedis = pool.getResource()) {
          Map<String, String> seed = new HashMap<>();
          DEFAULT_COORDINATES.forEach(
              (code, c) -> seed.put(code, c.getLatitude() + "," + c.getLongitude()));
          // Idempotent: replicas starting concurrently write identical values.
          jedis.hset(REDIS_COORDINATES_KEY, seed);
        }
      } catch (RuntimeException e) {
        LOGGER.log(Level.WARNING, "Redis unavailable for coordinates, using defaults.", e);
      }
    }
    JEDIS_POOL = pool;
  }
}
