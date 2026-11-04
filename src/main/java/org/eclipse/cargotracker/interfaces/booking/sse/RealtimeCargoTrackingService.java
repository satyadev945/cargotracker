package org.eclipse.cargotracker.interfaces.booking.sse;

import jakarta.annotation.PostConstruct;
import jakarta.annotation.PreDestroy;
import jakarta.ejb.Singleton;
import jakarta.enterprise.event.ObservesAsync;
import jakarta.inject.Inject;
import jakarta.json.bind.Jsonb;
import jakarta.json.bind.JsonbBuilder;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.Context;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.sse.OutboundSseEvent;
import jakarta.ws.rs.sse.Sse;
import jakarta.ws.rs.sse.SseBroadcaster;
import jakarta.ws.rs.sse.SseEventSink;
import java.util.logging.Level;
import java.util.logging.Logger;
import org.eclipse.cargotracker.domain.model.cargo.Cargo;
import org.eclipse.cargotracker.domain.model.cargo.CargoRepository;
import org.eclipse.cargotracker.infrastructure.events.cdi.CargoUpdated;
import redis.clients.jedis.DefaultJedisClientConfig;
import redis.clients.jedis.HostAndPort;
import redis.clients.jedis.Jedis;
import redis.clients.jedis.JedisPubSub;

/**
 * Sever-sent events service for tracking all cargo in real time.
 *
 * <p>SSE sinks are inherently bound to the local connection, but cargo update notifications are
 * externalized to Azure Cache for Redis (pub/sub) when {@code REDIS_HOST} is set, so that updates
 * performed on any replica are broadcast to the clients connected to every replica. Connection
 * settings are injected via environment variables (REDIS_HOST, REDIS_PORT, REDIS_PASSWORD,
 * REDIS_SSL), populated from Azure Key Vault through the CSI driver.
 */
@Singleton
@Path("/cargo")
public class RealtimeCargoTrackingService {
  @Inject private Logger logger;

  @Inject private CargoRepository cargoRepository;

  @Context private Sse sse;
  private SseBroadcaster broadcaster;

  private static final String CHANNEL = "cargotracker:cargo-updated";
  private final String redisHost = System.getenv("REDIS_HOST");
  private final int redisPort =
      Integer.parseInt(System.getenv().getOrDefault("REDIS_PORT", "6380"));
  private final String redisPassword = System.getenv("REDIS_PASSWORD");
  private final boolean redisSsl =
      Boolean.parseBoolean(System.getenv().getOrDefault("REDIS_SSL", "true"));
  private final Jsonb jsonb = JsonbBuilder.create();
  private volatile boolean running;
  private volatile JedisPubSub subscriber;
  private Thread subscriberThread;

  private boolean isRedisEnabled() {
    return redisHost != null && !redisHost.isBlank();
  }

  private Jedis newJedis() {
    DefaultJedisClientConfig.Builder config = DefaultJedisClientConfig.builder().ssl(redisSsl);
    if (redisPassword != null && !redisPassword.isEmpty()) {
      config.password(redisPassword);
    }
    return new Jedis(new HostAndPort(redisHost, redisPort), config.build());
  }

  @PostConstruct
  public void init() {
    broadcaster = sse.newBroadcaster();
    logger.log(Level.FINEST, "SSE broadcaster created.");

    if (isRedisEnabled()) {
      running = true;
      subscriberThread = new Thread(this::subscribeLoop, "cargo-updates-redis-subscriber");
      subscriberThread.setDaemon(true);
      subscriberThread.start();
    }
  }

  private void subscribeLoop() {
    while (running) {
      try (Jedis jedis = newJedis()) {
        subscriber =
            new JedisPubSub() {
              @Override
              public void onMessage(String channel, String message) {
                broadcaster.broadcast(
                    sse.newEventBuilder()
                        .mediaType(MediaType.APPLICATION_JSON_TYPE)
                        .data(String.class, message)
                        .build());
              }
            };
        jedis.subscribe(subscriber, CHANNEL);
      } catch (Exception e) {
        if (running) {
          logger.log(Level.WARNING, "Redis subscription failed, retrying.", e);
          try {
            Thread.sleep(5000);
          } catch (InterruptedException ie) {
            Thread.currentThread().interrupt();
            return;
          }
        }
      }
    }
  }

  @GET
  @Produces(MediaType.SERVER_SENT_EVENTS)
  public void tracking(@Context SseEventSink eventSink) {
    cargoRepository.findAll().stream().map(this::cargoToSseEvent).forEach(eventSink::send);

    broadcaster.register(eventSink);
    logger.log(Level.FINEST, "SSE event sink registered.");
  }

  @PreDestroy
  public void close() {
    running = false;
    JedisPubSub current = subscriber;
    if (current != null) {
      try {
        current.unsubscribe();
      } catch (Exception e) {
        logger.log(Level.FINEST, "Redis unsubscribe failed.", e);
      }
    }
    broadcaster.close();
    logger.log(Level.FINEST, "SSE broadcaster closed.");
  }

  public void onCargoUpdated(@ObservesAsync @CargoUpdated Cargo cargo) {
    logger.log(Level.FINEST, "SSE event broadcast for cargo: {0}", cargo);
    if (isRedisEnabled()) {
      // Publish through Redis; every replica (including this one) broadcasts to its own sinks.
      try (Jedis jedis = newJedis()) {
        jedis.publish(CHANNEL, jsonb.toJson(new RealtimeCargoTrackingViewAdapter(cargo)));
        return;
      } catch (Exception e) {
        logger.log(Level.WARNING, "Redis publish failed, broadcasting locally.", e);
      }
    }
    broadcaster.broadcast(cargoToSseEvent(cargo));
  }

  private OutboundSseEvent cargoToSseEvent(Cargo cargo) {
    return sse.newEventBuilder()
        .mediaType(MediaType.APPLICATION_JSON_TYPE)
        .data(new RealtimeCargoTrackingViewAdapter(cargo))
        .build();
  }
}
