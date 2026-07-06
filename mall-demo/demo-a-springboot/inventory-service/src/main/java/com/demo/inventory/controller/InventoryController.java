package com.demo.inventory.controller;

import com.demo.inventory.entity.Inventory;
import com.demo.inventory.service.InventoryService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.web.bind.annotation.*;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

@Slf4j
@RestController
@RequestMapping("/api/inventory")
@RequiredArgsConstructor
public class InventoryController {

    private final InventoryService inventoryService;

    @GetMapping("/{productId}")
    public Map<String, Object> getInventory(@PathVariable Long productId) {
        log.info("Get inventory request: {}", productId);
        return success(inventoryService.getInventory(productId));
    }

    @PostMapping("/deduct")
    public Map<String, Object> deductStock(@RequestBody Map<String, Object> body) {
        log.info("Deduct stock request: {}", body);
        Long productId = Long.valueOf(body.get("productId").toString());
        Integer quantity = Integer.valueOf(body.get("quantity").toString());
        inventoryService.deductStock(productId, quantity);
        return success("Stock deducted");
    }

    @PostMapping("/restore")
    public Map<String, Object> restoreStock(@RequestBody Map<String, Object> body) {
        log.info("Restore stock request: {}", body);
        Long productId = Long.valueOf(body.get("productId").toString());
        Integer quantity = Integer.valueOf(body.get("quantity").toString());
        inventoryService.restoreStock(productId, quantity);
        return success("Stock restored");
    }

    @PostMapping("/add")
    public Map<String, Object> addStock(@RequestBody Map<String, Object> body) {
        log.info("Add stock request: {}", body);
        Long productId = Long.valueOf(body.get("productId").toString());
        Integer quantity = Integer.valueOf(body.get("quantity").toString());
        inventoryService.addStock(productId, quantity);
        return success("Stock added");
    }

    @GetMapping
    public Map<String, Object> listInventory() {
        log.info("List inventory request");
        return success(inventoryService.listInventory());
    }

    @GetMapping("/health")
    public Map<String, Object> health() {
        Map<String, Object> health = new HashMap<>();
        health.put("status", "UP");
        health.put("service", "inventory-service");
        return health;
    }

    private Map<String, Object> success(Object data) {
        Map<String, Object> result = new HashMap<>();
        result.put("success", true);
        result.put("data", data);
        return result;
    }
}
