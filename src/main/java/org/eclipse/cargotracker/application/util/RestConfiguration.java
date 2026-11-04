package org.eclipse.cargotracker.application.util;

import jakarta.ws.rs.ApplicationPath;
import jakarta.ws.rs.core.Application;
import java.util.HashMap;
import java.util.Map;

/** Jakarta REST configuration. */
@ApplicationPath("rest")
public class RestConfiguration extends Application {

  // Equivalent to org.glassfish.jersey.server.ServerProperties.BV_SEND_ERROR_IN_RESPONSE;
  // literal used to avoid a compile-time dependency on GlassFish-specific classes.
  private static final String BV_SEND_ERROR_IN_RESPONSE =
      "jersey.config.beanValidation.enableOutputValidationErrorEntity.server";

  @Override
  public Map<String, Object> getProperties() {
    Map<String, Object> properties = new HashMap<String, Object>();
    properties.put(BV_SEND_ERROR_IN_RESPONSE, true);
    return properties;
  }
}
