package com.demo.notification.entity;

import lombok.Data;
import java.time.LocalDateTime;

@Data
public class NotificationRecord {
    private Long id;
    private String type;
    private String target;
    private String title;
    private String content;
    private Integer status;
    private String remark;
    private LocalDateTime createdAt;
}
