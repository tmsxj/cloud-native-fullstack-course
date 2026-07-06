package com.demo.order.controller;

import com.demo.order.entity.Order;
import com.demo.order.service.OrderService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.web.bind.annotation.*;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

@Slf4j
@RestController
@RequestMapping("/api/orders")
@RequiredArgsConstructor
public class OrderController {

    private final OrderService orderService;

    @PostMapping
    public Map<String, Object> createOrder(@RequestBody Map<String, Object> body) {
        log.info("Create order request: {}", body);
        Long userId = Long.valueOf(body.get("userId").toString());
        Long productId = Long.valueOf(body.get("productId").toString());
        Integer quantity = Integer.valueOf(body.get("quantity").toString());
        Order order = orderService.createOrder(userId, productId, quantity);
        return success(order);
    }

    @GetMapping("/{id}")
    public Map<String, Object> getOrder(@PathVariable Long id) {
        log.info("Get order request: {}", id);
        return success(orderService.getOrderById(id));
    }

    @GetMapping("/no/{orderNo}")
    public Map<String, Object> getOrderByNo(@PathVariable String orderNo) {
        log.info("Get order by orderNo: {}", orderNo);
        Order order = orderService.getOrderByNo(orderNo);
        if (order == null) {
            return fail("Order not found");
        }
        return success(order);
    }

    @GetMapping("/user/{userId}")
    public Map<String, Object> getOrdersByUser(@PathVariable Long userId) {
        log.info("Get orders by userId: {}", userId);
        return success(orderService.getOrdersByUserId(userId));
    }

    @GetMapping
    public Map<String, Object> listOrders() {
        log.info("List orders request");
        return success(orderService.listOrders());
    }

    @PostMapping("/demo")
    public Map<String, Object> generateDemoOrder() {
        log.info("Generate demo order request");
        Order order = orderService.generateDemoOrder();
        return success(order);
    }

    @GetMapping("/health")
    public Map<String, Object> health() {
        Map<String, Object> health = new HashMap<>();
        health.put("status", "UP");
        health.put("service", "order-service");
        return health;
    }

    private Map<String, Object> success(Object data) {
        Map<String, Object> result = new HashMap<>();
        result.put("success", true);
        result.put("data", data);
        return result;
    }

    private Map<String, Object> fail(String message) {
        Map<String, Object> result = new HashMap<>();
        result.put("success", false);
        result.put("message", message);
        return result;
    }
}
