package com.demo.inventory.entity;

import lombok.Data;
import java.time.LocalDateTime;

@Data
public class Inventory {
    private Long id;
    private Long productId;
    private String productName;
    private Integer stock;
    private Integer lockedStock;
    private Integer version;
    private LocalDateTime createdAt;
    private LocalDateTime updatedAt;
}
