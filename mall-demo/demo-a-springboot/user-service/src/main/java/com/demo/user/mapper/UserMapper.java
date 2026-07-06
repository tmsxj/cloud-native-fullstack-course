package com.demo.user.mapper;

import com.demo.user.entity.User;
import org.apache.ibatis.annotations.*;

import java.util.List;

@Mapper
public interface UserMapper {

    @Insert("INSERT INTO users(username, email, phone, password, status, created_at, updated_at) " +
            "VALUES(#{username}, #{email}, #{phone}, #{password}, #{status}, NOW(), NOW())")
    @Options(useGeneratedKeys = true, keyProperty = "id")
    int insert(User user);

    @Select("SELECT * FROM users WHERE id = #{id}")
    User findById(Long id);

    @Select("SELECT * FROM users WHERE username = #{username}")
    User findByUsername(String username);

    @Select("SELECT * FROM users WHERE email = #{email}")
    User findByEmail(String email);

    @Select("SELECT * FROM users")
    List<User> findAll();

    @Update("UPDATE users SET email=#{email}, phone=#{phone}, status=#{status}, updated_at=NOW() WHERE id=#{id}")
    int update(User user);

    @Delete("DELETE FROM users WHERE id = #{id}")
    int deleteById(Long id);
}
