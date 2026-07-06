package com.demo.inventory.consumer;

import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.stereotype.Component;

import java.util.Map;

@Slf4j
@Component
@RequiredArgsConstructor
public class InventoryEventConsumer {

    private final ObjectMapper objectMapper;

    @KafkaListener(topics = "order-events", groupId = "inventory-service-group")
    public void onOrderEvent(String message) {
        try {
            Map<String, Object> event = objectMapper.readValue(message, Map.class);
            String type = (String) event.get("type");
            log.info("Received order event: type={}, message={}", type, message);

            if ("ORDER_CANCELLED".equals(type)) {
                Long productId = Long.valueOf(event.get("productId").toString());
                Integer quantity = Integer.valueOf(event.get("quantity").toString());
                log.info("Order cancelled, restoring inventory - productId: {}, quantity: {}", productId, quantity);
                // Inventory restore would be handled here in production
            }
        } catch (Exception e) {
            log.error("Failed to process order event: {}", message, e);
        }
    }
}
