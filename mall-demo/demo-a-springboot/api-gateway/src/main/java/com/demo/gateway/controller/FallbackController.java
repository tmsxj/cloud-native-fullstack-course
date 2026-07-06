package com.demo.gateway.controller;

import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;

import java.util.HashMap;
import java.util.Map;

@RestController
public class FallbackController {

    @RequestMapping("/fallback/user")
    public Mono<Map<String, Object>> userFallback() {
        return Mono.just(fallback("user-service", "User service is currently unavailable"));
    }

    @RequestMapping("/fallback/order")
    public Mono<Map<String, Object>> orderFallback() {
        return Mono.just(fallback("order-service", "Order service is currently unavailable"));
    }

    @RequestMapping("/fallback/inventory")
    public Mono<Map<String, Object>> inventoryFallback() {
        return Mono.just(fallback("inventory-service", "Inventory service is currently unavailable"));
    }

    @RequestMapping("/fallback/payment")
    public Mono<Map<String, Object>> paymentFallback() {
        return Mono.just(fallback("payment-service", "Payment service is currently unavailable"));
    }

    @RequestMapping("/fallback/notification")
    public Mono<Map<String, Object>> notificationFallback() {
        return Mono.just(fallback("notification-service", "Notification service is currently unavailable"));
    }

    private Map<String, Object> fallback(String service, String message) {
        Map<String, Object> result = new HashMap<>();
        result.put("success", false);
        result.put("service", service);
        result.put("message", message);
        result.put("fallback", true);
        return result;
    }
}
