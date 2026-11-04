package org.eclipse.cargotracker.interfaces.booking.sse;

import java.util.EnumMap;
import java.util.HashMap;
import java.util.Map;
import org.eclipse.cargotracker.domain.model.cargo.Cargo;
import org.eclipse.cargotracker.domain.model.cargo.RoutingStatus;
import org.eclipse.cargotracker.domain.model.cargo.TransportStatus;
import org.eclipse.cargotracker.interfaces.RedisLookupCache;

/** View adapter for displaying a cargo in a realtime tracking context. */
public class RealtimeCargoTrackingViewAdapter {

  private static final String ROUTING_LABELS_KEY = "cargotracker:routing-status-labels";
  private static final String TRANSPORT_LABELS_KEY = "cargotracker:transport-status-labels";

  // Default labels; the shared cache is Azure Cache for Redis (see RedisLookupCache) when set.
  private static final Map<RoutingStatus, String> routingStatusLabels =
      new EnumMap<>(RoutingStatus.class);
  private static final Map<TransportStatus, String> transportStatusLabels =
      new EnumMap<>(TransportStatus.class);

  private final Cargo cargo;

  public RealtimeCargoTrackingViewAdapter(Cargo cargo) {
    this.cargo = cargo;
  }

  public String getTrackingId() {
    return cargo.getTrackingId().getIdString();
  }

  public String getRoutingStatus() {
    RoutingStatus status = cargo.getDelivery().getRoutingStatus();
    return RedisLookupCache.get(ROUTING_LABELS_KEY, status.name(), routingStatusLabels.get(status));
  }

  public boolean isMisdirected() {
    return cargo.getDelivery().isMisdirected();
  }

  public String getTransportStatus() {
    TransportStatus status = cargo.getDelivery().getTransportStatus();
    return RedisLookupCache.get(
        TRANSPORT_LABELS_KEY, status.name(), transportStatusLabels.get(status));
  }

  public boolean isAtDestination() {
    return cargo.getDelivery().isUnloadedAtDestination();
  }

  public LocationViewAdapter getOrigin() {
    return new LocationViewAdapter(cargo.getOrigin());
  }

  public LocationViewAdapter getLastKnownLocation() {
    return new LocationViewAdapter(cargo.getDelivery().getLastKnownLocation());
  }

  public LocationViewAdapter getLocation() {
    return cargo.getDelivery().getTransportStatus() == TransportStatus.NOT_RECEIVED
        ? getOrigin()
        : getLastKnownLocation();
  }

  public String getStatusCode() {
    RoutingStatus routingStatus = cargo.getDelivery().getRoutingStatus();

    if (routingStatus == RoutingStatus.NOT_ROUTED || routingStatus == RoutingStatus.MISROUTED) {
      return routingStatus.toString();
    }

    if (cargo.getDelivery().isMisdirected()) {
      return "MISDIRECTED";
    }

    if (cargo.getDelivery().isUnloadedAtDestination()) {
      return "AT_DESTINATION";
    }

    return cargo.getDelivery().getTransportStatus().toString();
  }

  static {
    routingStatusLabels.put(RoutingStatus.NOT_ROUTED, "Not routed");
    routingStatusLabels.put(RoutingStatus.ROUTED, "Routed");
    routingStatusLabels.put(RoutingStatus.MISROUTED, "Misrouted");

    transportStatusLabels.put(TransportStatus.NOT_RECEIVED, "Not received");
    transportStatusLabels.put(TransportStatus.IN_PORT, "In port");
    transportStatusLabels.put(TransportStatus.ONBOARD_CARRIER, "Onboard carrier");
    transportStatusLabels.put(TransportStatus.CLAIMED, "Claimed");
    transportStatusLabels.put(TransportStatus.UNKNOWN, "Unknown");

    // Publish the defaults to the shared Redis cache so all replicas see the same data.
    Map<String, String> routing = new HashMap<>();
    routingStatusLabels.forEach((k, v) -> routing.put(k.name(), v));
    RedisLookupCache.seed(ROUTING_LABELS_KEY, routing);
    Map<String, String> transport = new HashMap<>();
    transportStatusLabels.forEach((k, v) -> transport.put(k.name(), v));
    RedisLookupCache.seed(TRANSPORT_LABELS_KEY, transport);
  }
}
