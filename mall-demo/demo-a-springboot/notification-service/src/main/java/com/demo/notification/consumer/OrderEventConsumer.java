package com.demo.notification.consumer;

import com.demo.notification.service.NotificationService;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.stereotype.Component;

import java.util.Map;

@Slf4j
@Component
@RequiredArgsConstructor
public class OrderEventConsumer {

    private final NotificationService notificationService;
    private final ObjectMapper objectMapper;

    @KafkaListener(topics = "order-events", groupId = "notification-service-group")
    public void onOrderEvent(String message) {
        try {
            log.info("Received order event: {}", message);
            Map<String, Object> event = objectMapper.readValue(message, Map.class);
            notificationService.processOrderEvent(event);
            log.info("Order event processed successfully");
        } catch (Exception e) {
            log.error("Failed to process order event: {}", message, e);
        }
    }
}
