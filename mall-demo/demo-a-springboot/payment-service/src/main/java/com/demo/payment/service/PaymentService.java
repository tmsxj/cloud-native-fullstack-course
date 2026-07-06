package com.demo.payment.service;

import com.demo.payment.entity.Payment;
import com.demo.payment.mapper.PaymentMapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ThreadLocalRandom;

@Slf4j
@Service
@RequiredArgsConstructor
public class PaymentService {

    private final PaymentMapper paymentMapper;

    /**
     * Process payment with simulated success/failure (90% success rate)
     */
    public Payment processPayment(String orderId, Long userId, BigDecimal amount) {
        log.info("Processing payment - orderId: {}, userId: {}, amount: {}", orderId, userId, amount);

        // Simulate payment processing - 90% success rate
        boolean success = ThreadLocalRandom.current().nextInt(100) < 90;
        if (!success) {
            log.warn("Payment simulation failed for orderId: {}", orderId);
            throw new RuntimeException("Payment processing failed (simulated failure)");
        }

        Payment payment = new Payment();
        payment.setPaymentNo(generatePaymentNo());
        payment.setOrderId(orderId);
        payment.setUserId(userId);
        payment.setAmount(amount);
        payment.setMethod("ALIPAY");
        payment.setStatus(1); // SUCCESS
        payment.setRemark("Payment successful");
        paymentMapper.insert(payment);

        log.info("Payment processed successfully - paymentNo: {}", payment.getPaymentNo());
        return payment;
    }

    /**
     * Payment callback (simulated)
     */
    public Payment paymentCallback(String paymentNo, boolean success) {
        log.info("Payment callback - paymentNo: {}, success: {}", paymentNo, success);
        Payment payment = paymentMapper.findByPaymentNo(paymentNo);
        if (payment == null) {
            throw new RuntimeException("Payment not found: " + paymentNo);
        }

        payment.setStatus(success ? 1 : 2); // 1=SUCCESS, 2=FAILED
        payment.setRemark(success ? "Callback confirmed" : "Callback rejected");
        paymentMapper.updateStatus(payment);

        log.info("Payment callback processed - paymentNo: {}, newStatus: {}", paymentNo, payment.getStatus());
        return payment;
    }

    /**
     * Get payment by ID
     */
    public Payment getPaymentById(Long id) {
        log.info("Fetching payment by id: {}", id);
        Payment payment = paymentMapper.findById(id);
        if (payment == null) {
            throw new RuntimeException("Payment not found: " + id);
        }
        return payment;
    }

    /**
     * Get payment by payment number
     */
    public Payment getPaymentByNo(String paymentNo) {
        log.info("Fetching payment by paymentNo: {}", paymentNo);
        return paymentMapper.findByPaymentNo(paymentNo);
    }

    /**
     * List payments by order
     */
    public List<Payment> getPaymentsByOrder(String orderId) {
        log.info("Fetching payments for orderId: {}", orderId);
        return paymentMapper.findByOrderId(orderId);
    }

    /**
     * List all payments
     */
    public List<Payment> listPayments() {
        log.info("Listing all payments");
        return paymentMapper.findAll();
    }

    private String generatePaymentNo() {
        return "PAY" + LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyyMMddHHmmss"))
                + UUID.randomUUID().toString().substring(0, 6).toUpperCase();
    }
}
