-- =============================================
-- Mall Demo - User Database Schema
-- =============================================

CREATE DATABASE IF NOT EXISTS mall_user DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE mall_user;

DROP TABLE IF EXISTS `users`;

CREATE TABLE `users` (
    `id` BIGINT AUTO_INCREMENT PRIMARY KEY,
    `username` VARCHAR(50) NOT NULL,
    `email` VARCHAR(100) NOT NULL,
    `phone` VARCHAR(20) DEFAULT NULL,
    `status` VARCHAR(20) DEFAULT 'active',
    `created_at` DATETIME DEFAULT CURRENT_TIMESTAMP,
    `updated_at` DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY `uk_username` (`username`),
    KEY `idx_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 初始测试数据
INSERT INTO `users` (`username`, `email`, `phone`, `status`) VALUES
('testuser1', 'test1@mall.com', '13800000001', 'active'),
('testuser2', 'test2@mall.com', '13800000002', 'active'),
('testuser3', 'test3@mall.com', '13800000003', 'active');
