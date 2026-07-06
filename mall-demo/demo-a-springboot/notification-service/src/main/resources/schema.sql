CREATE DATABASE IF NOT EXISTS mall_notification DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE mall_notification;

CREATE TABLE IF NOT EXISTS notifications (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    type VARCHAR(32) NOT NULL COMMENT 'EMAIL, SMS, PUSH',
    target VARCHAR(128) NOT NULL,
    title VARCHAR(256) DEFAULT NULL,
    content TEXT,
    status INT DEFAULT 0 COMMENT '0-pending, 1-sent, 2-failed',
    remark VARCHAR(256) DEFAULT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_type (type),
    INDEX idx_target (target),
    INDEX idx_status (status),
    INDEX idx_created_at (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
