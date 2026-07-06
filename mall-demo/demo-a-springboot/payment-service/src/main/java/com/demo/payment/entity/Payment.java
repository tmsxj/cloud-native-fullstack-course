package com.demo.payment.entity;

import lombok.Data;
import java.math.BigDecimal;
import java.time.LocalDateTime;

@Data
public class Payment {
    private Long id;
    private String paymentNo;
    private String orderId;
    private Long userId;
    private BigDecimal amount;
    private String method;
    private Integer status;
    private String remark;
    private LocalDateTime createdAt;
    private LocalDateTime updatedAt;
}
