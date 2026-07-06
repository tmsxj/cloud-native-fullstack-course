package com.demo.inventory.service;

import com.demo.inventory.entity.Inventory;
import com.demo.inventory.mapper.InventoryMapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.cache.annotation.CacheEvict;
import org.springframework.cache.annotation.Cacheable;
import org.springframework.stereotype.Service;

import java.util.List;

@Slf4j
@Service
@RequiredArgsConstructor
public class InventoryService {

    private final InventoryMapper inventoryMapper;

    /**
     * Query inventory by product ID
     */
    @Cacheable(value = "inventory", key = "#productId")
    public Inventory getInventory(Long productId) {
        log.info("Fetching inventory for productId: {}", productId);
        Inventory inventory = inventoryMapper.findByProductId(productId);
        if (inventory == null) {
            throw new RuntimeException("Inventory not found for product: " + productId);
        }
        return inventory;
    }

    /**
     * Deduct stock (lock stock for order)
     */
    @CacheEvict(value = "inventory", key = "#productId")
    public boolean deductStock(Long productId, Integer quantity) {
        log.info("Deducting stock - productId: {}, quantity: {}", productId, quantity);
        int rows = inventoryMapper.deductStock(productId, quantity);
        if (rows == 0) {
            log.warn("Stock deduction failed - insufficient stock for productId: {}", productId);
            throw new RuntimeException("Insufficient stock for product: " + productId);
        }
        log.info("Stock deducted successfully - productId: {}, quantity: {}", productId, quantity);
        return true;
    }

    /**
     * Restore stock (release locked stock)
     */
    @CacheEvict(value = "inventory", key = "#productId")
    public boolean restoreStock(Long productId, Integer quantity) {
        log.info("Restoring stock - productId: {}, quantity: {}", productId, quantity);
        int rows = inventoryMapper.restoreStock(productId, quantity);
        if (rows == 0) {
            log.warn("Stock restore failed for productId: {}", productId);
            throw new RuntimeException("Failed to restore stock for product: " + productId);
        }
        log.info("Stock restored successfully - productId: {}, quantity: {}", productId, quantity);
        return true;
    }

    /**
     * Add stock (replenish inventory)
     */
    @CacheEvict(value = "inventory", key = "#productId")
    public boolean addStock(Long productId, Integer quantity) {
        log.info("Adding stock - productId: {}, quantity: {}", productId, quantity);
        inventoryMapper.addStock(productId, quantity);
        return true;
    }

    /**
     * List all inventory
     */
    public List<Inventory> listInventory() {
        log.info("Listing all inventory");
        return inventoryMapper.findAll();
    }
}
