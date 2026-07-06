CREATE DATABASE IF NOT EXISTS mall_inventory DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE mall_inventory;

CREATE TABLE IF NOT EXISTS inventory (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    product_id BIGINT NOT NULL UNIQUE,
    product_name VARCHAR(128) NOT NULL,
    stock INT NOT NULL DEFAULT 0,
    locked_stock INT NOT NULL DEFAULT 0,
    version INT NOT NULL DEFAULT 1,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_product_id (product_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Insert demo inventory data
INSERT IGNORE INTO inventory (product_id, product_name, stock) VALUES
(1, 'Spring Boot实战', 100),
(2, 'Docker入门指南', 80),
(3, 'Kubernetes权威指南', 50),
(4, '微服务架构设计', 120),
(5, '云原生应用开发', 60);
