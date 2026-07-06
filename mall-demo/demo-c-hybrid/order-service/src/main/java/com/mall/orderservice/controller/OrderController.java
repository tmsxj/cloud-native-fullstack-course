package com.mall.orderservice.controller;

import com.mall.orderservice.entity.Order;
import com.mall.orderservice.service.OrderService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

@Slf4j
@RestController
@RequestMapping("/orders")
@RequiredArgsConstructor
public class OrderController {

    private final OrderService orderService;

    @PostMapping
    public ResponseEntity<?> createOrder(@RequestBody Map<String, Object> request) {
        log.info("Creating order: {}", request);
        try {
            Order order = orderService.createOrder(
                    Long.valueOf(request.get("userId").toString()),
                    Long.valueOf(request.get("productId").toString()),
                    Integer.valueOf(request.get("quantity").toString())
            );
            return ResponseEntity.ok(Map.of("code", 200, "message", "Order created", "data", order));
        } catch (Exception e) {
            log.error("Failed to create order", e);
            return ResponseEntity.badRequest().body(Map.of("code", 400, "message", e.getMessage()));
        }
    }

    @GetMapping("/{id}")
    public ResponseEntity<?> getOrder(@PathVariable Long id) {
        return orderService.getOrder(id)
                .map(order -> ResponseEntity.ok(Map.of("code", 200, "data", order)))
                .orElse(ResponseEntity.notFound().build());
    }

    @GetMapping
    public ResponseEntity<?> listOrders(@RequestParam(required = false) Long userId) {
        if (userId != null) {
            return ResponseEntity.ok(Map.of("code", 200, "data", orderService.getOrdersByUser(userId)));
        }
        return ResponseEntity.ok(Map.of("code", 200, "data", orderService.getAllOrders()));
    }

    @PostMapping("/{id}/pay")
    public ResponseEntity<?> payOrder(@PathVariable Long id) {
        log.info("Paying order: {}", id);
        try {
            Order order = orderService.payOrder(id);
            return ResponseEntity.ok(Map.of("code", 200, "message", "Order paid", "data", order));
        } catch (Exception e) {
            log.error("Failed to pay order {}", id, e);
            return ResponseEntity.badRequest().body(Map.of("code", 400, "message", e.getMessage()));
        }
    }

    @PostMapping("/{id}/cancel")
    public ResponseEntity<?> cancelOrder(@PathVariable Long id) {
        log.info("Cancelling order: {}", id);
        try {
            Order order = orderService.cancelOrder(id);
            return ResponseEntity.ok(Map.of("code", 200, "message", "Order cancelled", "data", order));
        } catch (Exception e) {
            log.error("Failed to cancel order {}", id, e);
            return ResponseEntity.badRequest().body(Map.of("code", 400, "message", e.getMessage()));
        }
    }
}
