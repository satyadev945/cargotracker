package org.eclipse.cargotracker.interfaces.health;

import jakarta.enterprise.context.ApplicationScoped;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;

/** Simple health check endpoint exposed at /rest/health for container probes. */
@ApplicationScoped
@Path("/health")
public class HealthResource {

  @GET
  @Produces(MediaType.APPLICATION_JSON)
  public String health() {
    return "{\"status\":\"UP\"}";
  }
}
