package com.demo.notification.service;

import com.demo.notification.entity.NotificationRecord;
import com.demo.notification.mapper.NotificationMapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import java.util.List;
import java.util.Map;

@Slf4j
@Service
@RequiredArgsConstructor
public class NotificationService {

    private final NotificationMapper notificationMapper;

    /**
     * Send email notification (simulated)
     */
    public NotificationRecord sendEmail(String target, String title, String content) {
        log.info("Sending email to: {}, title: {}", target, title);
        NotificationRecord record = new NotificationRecord();
        record.setType("EMAIL");
        record.setTarget(target);
        record.setTitle(title);
        record.setContent(content);
        record.setStatus(1); // SENT
        record.setRemark("Email sent successfully (simulated)");
        notificationMapper.insert(record);
        log.info("Email sent - id: {}, target: {}", record.getId(), target);
        return record;
    }

    /**
     * Send SMS notification (simulated)
     */
    public NotificationRecord sendSms(String target, String content) {
        log.info("Sending SMS to: {}", target);
        NotificationRecord record = new NotificationRecord();
        record.setType("SMS");
        record.setTarget(target);
        record.setTitle("SMS Notification");
        record.setContent(content);
        record.setStatus(1); // SENT
        record.setRemark("SMS sent successfully (simulated)");
        notificationMapper.insert(record);
        log.info("SMS sent - id: {}, target: {}", record.getId(), target);
        return record;
    }

    /**
     * Process order event from Kafka
     */
    public void processOrderEvent(Map<String, Object> event) {
        String type = (String) event.get("type");
        String orderNo = (String) event.get("orderNo");
        Object userIdObj = event.get("userId");
        Object amountObj = event.get("amount");

        log.info("Processing order event - type: {}, orderNo: {}", type, orderNo);

        if ("ORDER_CREATED".equals(type)) {
            // Send order confirmation email
            String email = "user" + userIdObj + "@example.com";
            String title = "Order Confirmation - " + orderNo;
            String content = String.format("Dear User, your order %s has been created successfully. Amount: %s. Thank you for your purchase!",
                    orderNo, amountObj);
            sendEmail(email, title, content);

            // Send SMS notification
            String phone = "13800000000";
            String smsContent = String.format("Your order %s has been created. Amount: %s", orderNo, amountObj);
            sendSms(phone, smsContent);
        } else if ("PAYMENT_SUCCESS".equals(type)) {
            String email = "user" + userIdObj + "@example.com";
            String title = "Payment Confirmation - " + orderNo;
            String content = String.format("Dear User, payment for order %s has been confirmed. Amount: %s",
                    orderNo, amountObj);
            sendEmail(email, title, content);
        }
    }

    /**
     * List recent notifications
     */
    public List<NotificationRecord> getRecentNotifications(int limit) {
        return notificationMapper.findRecent(limit);
    }

    /**
     * List all notifications
     */
    public List<NotificationRecord> listNotifications() {
        return notificationMapper.findAll();
    }
}
