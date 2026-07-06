package com.mall.inventoryservice.controller;

import com.mall.inventoryservice.entity.Inventory;
import com.mall.inventoryservice.service.InventoryService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

@Slf4j
@RestController
@RequestMapping("/inventory")
@RequiredArgsConstructor
public class InventoryController {

    private final InventoryService inventoryService;

    @GetMapping("/product/{productId}")
    public ResponseEntity<?> getProductStock(@PathVariable Long productId) {
        Inventory inventory = inventoryService.getStock(productId);
        if (inventory == null) {
            return ResponseEntity.ok(Map.of("code", 200, "data", Map.of(
                    "product_id", productId, "stock", 0, "reserved_stock", 0)));
        }
        return ResponseEntity.ok(Map.of("code", 200, "data", inventory));
    }

    @PostMapping("/deduct")
    public ResponseEntity<?> deductStock(@RequestBody Map<String, Object> request) {
        log.info("Deducting stock: {}", request);
        try {
            Long productId = Long.valueOf(request.get("product_id").toString());
            Integer quantity = Integer.valueOf(request.get("quantity").toString());
            Inventory inventory = inventoryService.deductStock(productId, quantity);
            return ResponseEntity.ok(Map.of("code", 200, "message", "Stock deducted", "data", inventory));
        } catch (Exception e) {
            log.error("Failed to deduct stock", e);
            return ResponseEntity.badRequest().body(Map.of("code", 400, "message", e.getMessage()));
        }
    }

    @PostMapping("/restore")
    public ResponseEntity<?> restoreStock(@RequestBody Map<String, Object> request) {
        log.info("Restoring stock: {}", request);
        try {
            Long productId = Long.valueOf(request.get("product_id").toString());
            Integer quantity = Integer.valueOf(request.get("quantity").toString());
            Inventory inventory = inventoryService.restoreStock(productId, quantity);
            return ResponseEntity.ok(Map.of("code", 200, "message", "Stock restored", "data", inventory));
        } catch (Exception e) {
            log.error("Failed to restore stock", e);
            return ResponseEntity.badRequest().body(Map.of("code", 400, "message", e.getMessage()));
        }
    }
}
