package org.eclipse.cargotracker.application.util;

import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;

/** Simple liveness/readiness endpoint, available at /rest/health. */
@Path("/health")
public class HealthResource {

  @GET
  @Produces(MediaType.APPLICATION_JSON)
  public String health() {
    return "{\"status\":\"UP\"}";
  }
}
