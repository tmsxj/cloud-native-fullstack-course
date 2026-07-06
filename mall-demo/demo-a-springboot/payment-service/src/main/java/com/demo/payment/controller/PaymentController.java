package com.demo.payment.controller;

import com.demo.payment.entity.Payment;
import com.demo.payment.service.PaymentService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.web.bind.annotation.*;

import java.math.BigDecimal;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

@Slf4j
@RestController
@RequestMapping("/api/payments")
@RequiredArgsConstructor
public class PaymentController {

    private final PaymentService paymentService;

    @PostMapping("/pay")
    public Map<String, Object> pay(@RequestBody Map<String, Object> body) {
        log.info("Payment request: {}", body);
        try {
            String orderId = body.get("orderId").toString();
            Long userId = Long.valueOf(body.get("userId").toString());
            BigDecimal amount = new BigDecimal(body.get("amount").toString());
            Payment payment = paymentService.processPayment(orderId, userId, amount);
            Map<String, Object> result = success(payment);
            result.put("paymentNo", payment.getPaymentNo());
            return result;
        } catch (Exception e) {
            log.error("Payment failed", e);
            return fail(e.getMessage());
        }
    }

    @PostMapping("/callback/{paymentNo}")
    public Map<String, Object> callback(@PathVariable String paymentNo, @RequestBody Map<String, Object> body) {
        log.info("Payment callback: paymentNo={}, body={}", paymentNo, body);
        boolean success = Boolean.TRUE.equals(body.get("success"));
        Payment payment = paymentService.paymentCallback(paymentNo, success);
        return success(payment);
    }

    @GetMapping("/{id}")
    public Map<String, Object> getPayment(@PathVariable Long id) {
        log.info("Get payment request: {}", id);
        return success(paymentService.getPaymentById(id));
    }

    @GetMapping("/no/{paymentNo}")
    public Map<String, Object> getPaymentByNo(@PathVariable String paymentNo) {
        log.info("Get payment by paymentNo: {}", paymentNo);
        Payment payment = paymentService.getPaymentByNo(paymentNo);
        if (payment == null) {
            return fail("Payment not found");
        }
        return success(payment);
    }

    @GetMapping("/order/{orderId}")
    public Map<String, Object> getPaymentsByOrder(@PathVariable String orderId) {
        log.info("Get payments by orderId: {}", orderId);
        return success(paymentService.getPaymentsByOrder(orderId));
    }

    @GetMapping
    public Map<String, Object> listPayments() {
        log.info("List payments request");
        return success(paymentService.listPayments());
    }

    @GetMapping("/health")
    public Map<String, Object> health() {
        Map<String, Object> health = new HashMap<>();
        health.put("status", "UP");
        health.put("service", "payment-service");
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
