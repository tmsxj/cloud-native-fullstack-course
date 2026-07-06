-- =============================================
-- Mall Demo - Inventory Database Schema
-- =============================================

CREATE DATABASE IF NOT EXISTS mall_inventory DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE mall_inventory;

DROP TABLE IF EXISTS `inventory`;

CREATE TABLE `inventory` (
    `id` BIGINT AUTO_INCREMENT PRIMARY KEY,
    `product_id` BIGINT NOT NULL,
    `stock` INT NOT NULL DEFAULT 0,
    `reserved_stock` INT DEFAULT 0,
    `created_at` DATETIME DEFAULT CURRENT_TIMESTAMP,
    `updated_at` DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY `uk_product_id` (`product_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 初始库存数据
INSERT INTO `inventory` (`product_id`, `stock`, `reserved_stock`) VALUES
(1001, 500, 0),
(1002, 300, 0),
(1003, 200, 0),
(1004, 1000, 0),
(1005, 150, 0);
