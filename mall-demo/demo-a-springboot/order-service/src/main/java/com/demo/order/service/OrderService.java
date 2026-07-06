package com.demo.order.service;

import com.demo.order.entity.Order;
import com.demo.order.mapper.OrderMapper;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestTemplate;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ThreadLocalRandom;
import java.util.UUID;

@Slf4j
@Service
@RequiredArgsConstructor
public class OrderService {

    private final OrderMapper orderMapper;
    private final RestTemplate restTemplate;
    private final KafkaTemplate<String, String> kafkaTemplate;
    private final ObjectMapper objectMapper;

    private static final String USER_SERVICE = "http://user-service";
    private static final String INVENTORY_SERVICE = "http://inventory-service";
    private static final String PAYMENT_SERVICE = "http://payment-service";

    /**
     * Create order - full call chain:
     * 1. Verify user via user-service
     * 2. Deduct inventory via inventory-service
     * 3. Process payment via payment-service
     * 4. Send Kafka message for notification
     */
    public Order createOrder(Long userId, Long productId, Integer quantity) {
        log.info("Creating order - userId: {}, productId: {}, quantity: {}", userId, productId, quantity);

        // Step 1: Verify user
        Map<String, Object> userResult = restTemplate.getForObject(
                USER_SERVICE + "/api/users/{id}/verify", Map.class, userId);
        if (userResult == null || !Boolean.TRUE.equals(userResult.get("valid"))) {
            throw new RuntimeException("User verification failed for userId: " + userId);
        }
        log.info("User verified: {}", userId);

        // Step 2: Deduct inventory
        Map<String, Object> deductRequest = new HashMap<>();
        deductRequest.put("productId", productId);
        deductRequest.put("quantity", quantity);
        @SuppressWarnings("unchecked")
        Map<String, Object> inventoryResult = restTemplate.postForObject(
                INVENTORY_SERVICE + "/api/inventory/deduct", deductRequest, Map.class);
        if (inventoryResult == null || !Boolean.TRUE.equals(inventoryResult.get("success"))) {
            throw new RuntimeException("Inventory deduction failed: " + inventoryResult);
        }
        log.info("Inventory deducted - productId: {}, quantity: {}", productId, quantity);

        // Step 3: Process payment
        BigDecimal amount = new BigDecimal("99.99").multiply(new BigDecimal(quantity));
        Map<String, Object> paymentRequest = new HashMap<>();
        paymentRequest.put("orderId", "pending");
        paymentRequest.put("userId", userId);
        paymentRequest.put("amount", amount);
        @SuppressWarnings("unchecked")
        Map<String, Object> paymentResult = restTemplate.postForObject(
                PAYMENT_SERVICE + "/api/payments/pay", paymentRequest, Map.class);
        if (paymentResult == null || !Boolean.TRUE.equals(paymentResult.get("success"))) {
            // Payment failed, restore inventory
            log.warn("Payment failed, restoring inventory");
            Map<String, Object> restoreRequest = new HashMap<>();
            restoreRequest.put("productId", productId);
            restoreRequest.put("quantity", quantity);
            restTemplate.postForObject(
                    INVENTORY_SERVICE + "/api/inventory/restore", restoreRequest, Map.class);
            throw new RuntimeException("Payment failed: " + paymentResult);
        }
        String paymentNo = (String) paymentResult.get("paymentNo");
        log.info("Payment processed - paymentNo: {}", paymentNo);

        // Step 4: Create order record
        Order order = new Order();
        order.setOrderNo(generateOrderNo());
        order.setUserId(userId);
        order.setProductId(productId);
        order.setQuantity(quantity);
        order.setAmount(amount);
        order.setStatus(1); // PAID
        order.setPaymentNo(paymentNo);
        orderMapper.insert(order);
        log.info("Order created - orderNo: {}, id: {}", order.getOrderNo(), order.getId());

        // Step 5: Send Kafka notification
        sendOrderNotification(order);

        return order;
    }

    /**
     * Get order by ID
     */
    public Order getOrderById(Long id) {
        log.info("Fetching order by id: {}", id);
        Order order = orderMapper.findById(id);
        if (order == null) {
            throw new RuntimeException("Order not found: " + id);
        }
        return order;
    }

    /**
     * Get order by order number
     */
    public Order getOrderByNo(String orderNo) {
        log.info("Fetching order by orderNo: {}", orderNo);
        return orderMapper.findByOrderNo(orderNo);
    }

    /**
     * List orders by user
     */
    public List<Order> getOrdersByUserId(Long userId) {
        log.info("Fetching orders for userId: {}", userId);
        return orderMapper.findByUserId(userId);
    }

    /**
     * List all orders
     */
    public List<Order> listOrders() {
        log.info("Listing all orders");
        return orderMapper.findAll();
    }

    /**
     * Generate simulated order data for monitoring demo
     */
    public Order generateDemoOrder() {
        Long userId = ThreadLocalRandom.current().nextLong(1, 4);
        Long productId = ThreadLocalRandom.current().nextLong(1, 6);
        int quantity = ThreadLocalRandom.current().nextInt(1, 4);
        return createOrder(userId, productId, quantity);
    }

    private String generateOrderNo() {
        return "ORD" + LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyyMMddHHmmss"))
                + UUID.randomUUID().toString().substring(0, 6).toUpperCase();
    }

    private void sendOrderNotification(Order order) {
        try {
            Map<String, Object> notification = new HashMap<>();
            notification.put("type", "ORDER_CREATED");
            notification.put("orderNo", order.getOrderNo());
            notification.put("userId", order.getUserId());
            notification.put("amount", order.getAmount());
            notification.put("status", order.getStatus());
            notification.put("timestamp", System.currentTimeMillis());

            String message = objectMapper.writeValueAsString(notification);
            kafkaTemplate.send("order-events", order.getOrderNo(), message);
            log.info("Kafka notification sent for order: {}", order.getOrderNo());
        } catch (Exception e) {
            log.error("Failed to send Kafka notification for order: {}", order.getOrderNo(), e);
        }
    }
}
