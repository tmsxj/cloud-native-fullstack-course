package com.mall.orderservice.service;

import com.mall.orderservice.entity.Order;
import com.mall.orderservice.repository.OrderRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestTemplate;

import java.math.BigDecimal;
import java.util.List;
import java.util.Map;
import java.util.Optional;

@Slf4j
@Service
@RequiredArgsConstructor
public class OrderService {

    private final OrderRepository orderRepository;
    private final KafkaTemplate<String, String> kafkaTemplate;
    private final RestTemplate restTemplate;

    private static final String INVENTORY_SERVICE_URL = "http://inventory-service:8080";
    private static final String PAYMENT_SERVICE_URL = "http://payment-service:8080";
    private static final String ORDER_EVENTS_TOPIC = "order-events";

    public Order createOrder(Long userId, Long productId, Integer quantity) {
        // 1. 检查库存
        checkInventory(productId, quantity);

        // 2. 扣减库存
        deductInventory(productId, quantity);

        // 3. 创建订单
        Order order = new Order();
        order.setUserId(userId);
        order.setProductId(productId);
        order.setQuantity(quantity);
        order.setAmount(calculateAmount(productId, quantity));
        order.setStatus("PENDING");
        order = orderRepository.save(order);

        // 4. 发送订单创建事件到Kafka
        publishOrderEvent("ORDER_CREATED", order);

        log.info("Order created: id={}, userId={}, productId={}, quantity={}",
                order.getId(), userId, productId, quantity);
        return order;
    }

    public Optional<Order> getOrder(Long id) {
        return orderRepository.findById(id);
    }

    public List<Order> getOrdersByUser(Long userId) {
        return orderRepository.findByUserId(userId);
    }

    public List<Order> getAllOrders() {
        return orderRepository.findAll();
    }

    public Order payOrder(Long id) {
        Order order = orderRepository.findById(id)
                .orElseThrow(() -> new RuntimeException("Order not found: " + id));

        if (!"PENDING".equals(order.getStatus())) {
            throw new RuntimeException("Order is not payable, current status: " + order.getStatus());
        }

        // 调用支付服务
        try {
            @SuppressWarnings("unchecked")
            Map<String, Object> paymentResult = restTemplate.postForObject(
                    PAYMENT_SERVICE_URL + "/payments",
                    Map.of("order_id", order.getId().toString(),
                            "amount", order.getAmount(),
                            "method", "alipay"),
                    Map.class
            );

            if (paymentResult != null && Integer.valueOf(paymentResult.get("code").toString()) == 200) {
                order.setStatus("PAID");
                order.setPaymentId(paymentResult.get("data").toString());
                orderRepository.save(order);
                publishOrderEvent("ORDER_PAID", order);
                log.info("Order paid: id={}", id);
            } else {
                order.setStatus("FAILED");
                orderRepository.save(order);
                // 恢复库存
                restoreInventory(order.getProductId(), order.getQuantity());
                publishOrderEvent("PAYMENT_FAILED", order);
                throw new RuntimeException("Payment failed for order: " + id);
            }
        } catch (Exception e) {
            order.setStatus("FAILED");
            orderRepository.save(order);
            restoreInventory(order.getProductId(), order.getQuantity());
            publishOrderEvent("PAYMENT_FAILED", order);
            throw new RuntimeException("Payment error: " + e.getMessage());
        }

        return order;
    }

    public Order cancelOrder(Long id) {
        Order order = orderRepository.findById(id)
                .orElseThrow(() -> new RuntimeException("Order not found: " + id));

        if ("PAID".equals(order.getStatus()) || "PENDING".equals(order.getStatus())) {
            order.setStatus("CANCELLED");
            orderRepository.save(order);

            // 恢复库存
            restoreInventory(order.getProductId(), order.getQuantity());

            publishOrderEvent("ORDER_CANCELLED", order);
            log.info("Order cancelled: id={}", id);
        } else {
            throw new RuntimeException("Order cannot be cancelled, current status: " + order.getStatus());
        }

        return order;
    }

    private void checkInventory(Long productId, Integer quantity) {
        try {
            @SuppressWarnings("unchecked")
            Map<String, Object> result = restTemplate.getForObject(
                    INVENTORY_SERVICE_URL + "/inventory/product/" + productId,
                    Map.class
            );
            if (result != null) {
                @SuppressWarnings("unchecked")
                Map<String, Object> data = (Map<String, Object>) result.get("data");
                int stock = Integer.parseInt(data.get("stock").toString());
                if (stock < quantity) {
                    throw new RuntimeException("Insufficient inventory. Available: " + stock + ", Required: " + quantity);
                }
            }
        } catch (RuntimeException e) {
            throw e;
        } catch (Exception e) {
            log.warn("Inventory check failed, proceeding anyway: {}", e.getMessage());
        }
    }

    private void deductInventory(Long productId, Integer quantity) {
        try {
            restTemplate.postForObject(
                    INVENTORY_SERVICE_URL + "/inventory/deduct",
                    Map.of("product_id", productId, "quantity", quantity),
                    Map.class
            );
        } catch (Exception e) {
            log.warn("Inventory deduction failed: {}", e.getMessage());
        }
    }

    private void restoreInventory(Long productId, Integer quantity) {
        try {
            restTemplate.postForObject(
                    INVENTORY_SERVICE_URL + "/inventory/restore",
                    Map.of("product_id", productId, "quantity", quantity),
                    Map.class
            );
        } catch (Exception e) {
            log.warn("Inventory restore failed: {}", e.getMessage());
        }
    }

    private BigDecimal calculateAmount(Long productId, Integer quantity) {
        // 简化：每件商品固定价格
        return BigDecimal.valueOf(productId * 10.0).multiply(BigDecimal.valueOf(quantity));
    }

    private void publishOrderEvent(String eventType, Order order) {
        try {
            String event = String.format(
                    "{\"event_type\":\"%s\",\"order_id\":\"%s\",\"user_id\":\"%s\",\"amount\":%.2f,\"status\":\"%s\"}",
                    eventType, order.getId(), order.getUserId(), order.getAmount(), order.getStatus()
            );
            kafkaTemplate.send(ORDER_EVENTS_TOPIC, order.getId().toString(), event);
            log.info("Published order event: type={}, orderId={}", eventType, order.getId());
        } catch (Exception e) {
            log.error("Failed to publish order event: {}", e.getMessage());
        }
    }
}
