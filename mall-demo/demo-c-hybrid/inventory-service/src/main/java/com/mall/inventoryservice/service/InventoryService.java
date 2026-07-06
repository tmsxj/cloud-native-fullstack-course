package com.mall.inventoryservice.service;

import com.mall.inventoryservice.entity.Inventory;
import com.mall.inventoryservice.repository.InventoryRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Slf4j
@Service
@RequiredArgsConstructor
public class InventoryService {

    private final InventoryRepository inventoryRepository;

    public Inventory getStock(Long productId) {
        return inventoryRepository.findByProductId(productId).orElse(null);
    }

    @Transactional
    public Inventory deductStock(Long productId, Integer quantity) {
        Inventory inventory = inventoryRepository.findByProductId(productId)
                .orElseGet(() -> {
                    Inventory newInv = new Inventory();
                    newInv.setProductId(productId);
                    newInv.setStock(1000); // 默认库存
                    newInv.setReservedStock(0);
                    return inventoryRepository.save(newInv);
                });

        if (inventory.getStock() < quantity) {
            throw new RuntimeException("Insufficient stock. Available: " + inventory.getStock() + ", Required: " + quantity);
        }

        inventory.setStock(inventory.getStock() - quantity);
        inventory.setReservedStock(inventory.getReservedStock() + quantity);
        inventory = inventoryRepository.save(inventory);

        log.info("Stock deducted: productId={}, quantity={}, remaining={}",
                productId, quantity, inventory.getStock());
        return inventory;
    }

    @Transactional
    public Inventory restoreStock(Long productId, Integer quantity) {
        Inventory inventory = inventoryRepository.findByProductId(productId)
                .orElseThrow(() -> new RuntimeException("Inventory not found for product: " + productId));

        inventory.setStock(inventory.getStock() + quantity);
        inventory.setReservedStock(Math.max(0, inventory.getReservedStock() - quantity));
        inventory = inventoryRepository.save(inventory);

        log.info("Stock restored: productId={}, quantity={}, remaining={}",
                productId, quantity, inventory.getStock());
        return inventory;
    }
}
