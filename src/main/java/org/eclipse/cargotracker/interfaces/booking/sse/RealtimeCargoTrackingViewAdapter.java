package org.eclipse.cargotracker.interfaces.booking.sse;

import org.eclipse.cargotracker.domain.model.cargo.Cargo;
import org.eclipse.cargotracker.domain.model.cargo.RoutingStatus;
import org.eclipse.cargotracker.domain.model.cargo.TransportStatus;

/** View adapter for displaying a cargo in a realtime tracking context. */
public class RealtimeCargoTrackingViewAdapter {

  private final Cargo cargo;

  public RealtimeCargoTrackingViewAdapter(Cargo cargo) {
    this.cargo = cargo;
  }

  public String getTrackingId() {
    return cargo.getTrackingId().getIdString();
  }

  public String getRoutingStatus() {
    return routingStatusLabel(cargo.getDelivery().getRoutingStatus());
  }

  public boolean isMisdirected() {
    return cargo.getDelivery().isMisdirected();
  }

  public String getTransportStatus() {
    return transportStatusLabel(cargo.getDelivery().getTransportStatus());
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

  // Labels are resolved statelessly (no in-process cache), so every replica returns the same value.
  private static String routingStatusLabel(RoutingStatus status) {
    switch (status) {
      case NOT_ROUTED:
        return "Not routed";
      case ROUTED:
        return "Routed";
      case MISROUTED:
        return "Misrouted";
      default:
        return null;
    }
  }

  private static String transportStatusLabel(TransportStatus status) {
    switch (status) {
      case NOT_RECEIVED:
        return "Not received";
      case IN_PORT:
        return "In port";
      case ONBOARD_CARRIER:
        return "Onboard carrier";
      case CLAIMED:
        return "Claimed";
      case UNKNOWN:
        return "Unknown";
      default:
        return null;
    }
  }
}
