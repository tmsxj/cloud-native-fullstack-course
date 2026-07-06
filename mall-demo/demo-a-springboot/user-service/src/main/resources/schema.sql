CREATE DATABASE IF NOT EXISTS mall_user DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE mall_user;

CREATE TABLE IF NOT EXISTS users (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(64) NOT NULL UNIQUE,
    email VARCHAR(128) DEFAULT NULL,
    phone VARCHAR(20) DEFAULT NULL,
    password VARCHAR(128) NOT NULL,
    status INT DEFAULT 1 COMMENT '1-active, 0-disabled',
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_username (username),
    INDEX idx_email (email)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Insert demo users
INSERT IGNORE INTO users (username, email, phone, password, status) VALUES
('demo_user', 'demo@example.com', '13800000001', 'encoded_password', 1),
('test_user', 'test@example.com', '13800000002', 'encoded_password', 1),
('vip_user', 'vip@example.com', '13800000003', 'encoded_password', 1);
