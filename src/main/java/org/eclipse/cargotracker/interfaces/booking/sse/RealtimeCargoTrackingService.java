package org.eclipse.cargotracker.interfaces.booking.sse;

import jakarta.annotation.PostConstruct;
import jakarta.annotation.PreDestroy;
import jakarta.ejb.Singleton;
import jakarta.enterprise.event.ObservesAsync;
import jakarta.inject.Inject;
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
import org.eclipse.cargotracker.domain.model.cargo.TrackingId;
import org.eclipse.cargotracker.infrastructure.events.cdi.CargoUpdated;
import redis.clients.jedis.Jedis;
import redis.clients.jedis.JedisPool;
import redis.clients.jedis.JedisPubSub;

/** Sever-sent events service for tracking all cargo in real time. */
@Singleton
@Path("/cargo")
public class RealtimeCargoTrackingService {
  @Inject private Logger logger;

  @Inject private CargoRepository cargoRepository;

  @Context private Sse sse;
  private SseBroadcaster broadcaster;

  // Cargo updates are fanned out to every replica through a Redis (ElastiCache) channel so that
  // SSE clients connected to any pod receive updates raised on any other pod. When REDIS_HOST is
  // not set, the service falls back to local-only broadcasting.
  private static final String REDIS_CHANNEL = "cargotracker:cargo-updated";
  private JedisPool jedisPool;
  private JedisPubSub redisSubscriber;
  private volatile boolean running;

  @PostConstruct
  public void init() {
    broadcaster = sse.newBroadcaster();
    logger.log(Level.FINEST, "SSE broadcaster created.");

    String redisHost = System.getenv("REDIS_HOST");
    if (redisHost != null && !redisHost.isBlank()) {
      int redisPort = Integer.parseInt(System.getenv().getOrDefault("REDIS_PORT", "6379"));
      jedisPool = new JedisPool(redisHost, redisPort);
      running = true;
      startRedisSubscriber();
    }
  }

  private void startRedisSubscriber() {
    redisSubscriber =
        new JedisPubSub() {
          @Override
          public void onMessage(String channel, String trackingId) {
            try {
              Cargo cargo = cargoRepository.find(new TrackingId(trackingId));
              if (cargo != null) {
                broadcaster.broadcast(cargoToSseEvent(cargo));
              }
            } catch (RuntimeException e) {
              logger.log(Level.WARNING, "Failed to broadcast cargo update from Redis.", e);
            }
          }
        };

    Thread subscriberThread =
        new Thread(
            () -> {
              while (running) {
                try (Jedis jedis = jedisPool.getResource()) {
                  jedis.subscribe(redisSubscriber, REDIS_CHANNEL);
                } catch (RuntimeException e) {
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
            },
            "cargo-tracker-redis-subscriber");
    subscriberThread.setDaemon(true);
    subscriberThread.start();
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
    if (redisSubscriber != null) {
      try {
        redisSubscriber.unsubscribe();
      } catch (RuntimeException e) {
        logger.log(Level.FINE, "Redis unsubscribe failed.", e);
      }
    }
    if (jedisPool != null) {
      jedisPool.close();
    }
    broadcaster.close();
    logger.log(Level.FINEST, "SSE broadcaster closed.");
  }

  public void onCargoUpdated(@ObservesAsync @CargoUpdated Cargo cargo) {
    logger.log(Level.FINEST, "SSE event broadcast for cargo: {0}", cargo);
    if (jedisPool != null) {
      try (Jedis jedis = jedisPool.getResource()) {
        jedis.publish(REDIS_CHANNEL, cargo.getTrackingId().getIdString());
        return;
      } catch (RuntimeException e) {
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
