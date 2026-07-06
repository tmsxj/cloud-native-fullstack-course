package com.demo.order.entity;

import lombok.Data;
import java.math.BigDecimal;
import java.time.LocalDateTime;

@Data
public class Order {
    private Long id;
    private String orderNo;
    private Long userId;
    private Long productId;
    private Integer quantity;
    private BigDecimal amount;
    private Integer status;
    private String paymentNo;
    private LocalDateTime createdAt;
    private LocalDateTime updatedAt;
}
