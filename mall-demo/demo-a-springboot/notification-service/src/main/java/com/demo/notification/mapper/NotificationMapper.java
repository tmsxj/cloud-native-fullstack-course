package com.demo.notification.mapper;

import com.demo.notification.entity.NotificationRecord;
import org.apache.ibatis.annotations.*;

import java.util.List;

@Mapper
public interface NotificationMapper {

    @Insert("INSERT INTO notifications(type, target, title, content, status, remark, created_at) " +
            "VALUES(#{type}, #{target}, #{title}, #{content}, #{status}, #{remark}, NOW())")
    @Options(useGeneratedKeys = true, keyProperty = "id")
    int insert(NotificationRecord record);

    @Select("SELECT * FROM notifications WHERE id = #{id}")
    NotificationRecord findById(Long id);

    @Select("SELECT * FROM notifications ORDER BY created_at DESC LIMIT #{limit}")
    List<NotificationRecord> findRecent(int limit);

    @Select("SELECT * FROM notifications")
    List<NotificationRecord> findAll();
}
