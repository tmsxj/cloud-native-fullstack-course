package com.demo.gateway.controller;

import lombok.extern.slf4j.Slf4j;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.HashMap;
import java.util.Map;

@Slf4j
@RestController
public class GatewayHealthController {

    @GetMapping("/health")
    public Map<String, Object> health() {
        Map<String, Object> health = new HashMap<>();
        health.put("status", "UP");
        health.put("service", "api-gateway");
        return health;
    }

    @GetMapping("/gateway/routes")
    public Map<String, Object> routes() {
        Map<String, Object> result = new HashMap<>();
        result.put("user-service", "/api/users/**");
        result.put("order-service", "/api/orders/**");
        result.put("inventory-service", "/api/inventory/**");
        result.put("payment-service", "/api/payments/**");
        result.put("notification-service", "/api/notifications/**");
        return result;
    }
}
