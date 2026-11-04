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
import org.eclipse.cargotracker.domain.model.location.Location;
import org.eclipse.cargotracker.domain.model.location.UnLocode;

/**
 * At the moment, coordinates are produced by a simple factory. It may be converted to a repository
 * if coordinates become a domain layer concern.
 */
public class CoordinatesFactory {

  private static final String CACHE_KEY = "cargotracker:coordinates";

  // Default data; the shared cache is Azure Cache for Redis (see RedisLookupCache) when configured.
  private static final Map<String, Coordinates> COORDINATES_MAP;

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
    Coordinates defaults = COORDINATES_MAP.get(unLocode);
    String cached =
        RedisLookupCache.get(
            CACHE_KEY,
            unLocode,
            defaults == null ? null : defaults.getLatitude() + "," + defaults.getLongitude());
    if (cached == null) {
      return null;
    }
    if (defaults != null && cached.equals(defaults.getLatitude() + "," + defaults.getLongitude())) {
      return defaults;
    }
    try {
      String[] parts = cached.split(",");
      return new Coordinates(Double.parseDouble(parts[0]), Double.parseDouble(parts[1]));
    } catch (RuntimeException e) {
      return defaults;
    }
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

    COORDINATES_MAP = Map.copyOf(map);

    // Publish the defaults to the shared Redis cache so all replicas see the same data.
    Map<String, String> seed = new HashMap<>();
    COORDINATES_MAP.forEach((k, v) -> seed.put(k, v.getLatitude() + "," + v.getLongitude()));
    RedisLookupCache.seed(CACHE_KEY, seed);
  }
}
