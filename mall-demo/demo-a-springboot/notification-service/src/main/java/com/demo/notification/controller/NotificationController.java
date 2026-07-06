package com.demo.notification.controller;

import com.demo.notification.entity.NotificationRecord;
import com.demo.notification.service.NotificationService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.web.bind.annotation.*;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

@Slf4j
@RestController
@RequestMapping("/api/notifications")
@RequiredArgsConstructor
public class NotificationController {

    private final NotificationService notificationService;

    @PostMapping("/email")
    public Map<String, Object> sendEmail(@RequestBody Map<String, String> body) {
        log.info("Send email request: {}", body.get("target"));
        NotificationRecord record = notificationService.sendEmail(
                body.get("target"), body.get("title"), body.get("content"));
        return success(record);
    }

    @PostMapping("/sms")
    public Map<String, Object> sendSms(@RequestBody Map<String, String> body) {
        log.info("Send SMS request: {}", body.get("target"));
        NotificationRecord record = notificationService.sendSms(
                body.get("target"), body.get("content"));
        return success(record);
    }

    @GetMapping("/recent")
    public Map<String, Object> getRecent(@RequestParam(defaultValue = "20") int limit) {
        log.info("Get recent notifications: limit={}", limit);
        return success(notificationService.getRecentNotifications(limit));
    }

    @GetMapping
    public Map<String, Object> listNotifications() {
        log.info("List notifications request");
        return success(notificationService.listNotifications());
    }

    @GetMapping("/health")
    public Map<String, Object> health() {
        Map<String, Object> health = new HashMap<>();
        health.put("status", "UP");
        health.put("service", "notification-service");
        return health;
    }

    private Map<String, Object> success(Object data) {
        Map<String, Object> result = new HashMap<>();
        result.put("success", true);
        result.put("data", data);
        return result;
    }
}
