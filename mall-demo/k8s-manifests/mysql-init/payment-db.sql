-- =============================================
-- Mall Demo - Payment Database Schema
-- =============================================

CREATE DATABASE IF NOT EXISTS mall_payment DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE mall_payment;

DROP TABLE IF EXISTS `payments`;

CREATE TABLE `payments` (
    `id` VARCHAR(100) PRIMARY KEY,
    `order_id` VARCHAR(100) NOT NULL,
    `amount` DECIMAL(10,2) NOT NULL,
    `method` VARCHAR(50) NOT NULL,
    `status` VARCHAR(20) DEFAULT 'pending',
    `transaction_id` VARCHAR(200) DEFAULT NULL,
    `created_at` DATETIME DEFAULT CURRENT_TIMESTAMP,
    `updated_at` DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    KEY `idx_order_id` (`order_id`),
    KEY `idx_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
