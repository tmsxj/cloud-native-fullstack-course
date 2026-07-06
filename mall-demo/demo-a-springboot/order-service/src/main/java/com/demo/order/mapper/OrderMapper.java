package com.demo.order.mapper;

import com.demo.order.entity.Order;
import org.apache.ibatis.annotations.*;

import java.util.List;

@Mapper
public interface OrderMapper {

    @Insert("INSERT INTO orders(order_no, user_id, product_id, quantity, amount, status, payment_no, created_at, updated_at) " +
            "VALUES(#{orderNo}, #{userId}, #{productId}, #{quantity}, #{amount}, #{status}, #{paymentNo}, NOW(), NOW())")
    @Options(useGeneratedKeys = true, keyProperty = "id")
    int insert(Order order);

    @Select("SELECT * FROM orders WHERE id = #{id}")
    Order findById(Long id);

    @Select("SELECT * FROM orders WHERE order_no = #{orderNo}")
    @Results({
            @Result(property = "orderNo", column = "order_no"),
            @Result(property = "userId", column = "user_id"),
            @Result(property = "productId", column = "product_id"),
            @Result(property = "paymentNo", column = "payment_no"),
            @Result(property = "createdAt", column = "created_at"),
            @Result(property = "updatedAt", column = "updated_at")
    })
    Order findByOrderNo(String orderNo);

    @Select("SELECT * FROM orders WHERE user_id = #{userId}")
    List<Order> findByUserId(Long userId);

    @Select("SELECT * FROM orders")
    List<Order> findAll();

    @Update("UPDATE orders SET status=#{status}, payment_no=#{paymentNo}, updated_at=NOW() WHERE id=#{id}")
    int updateStatus(Order order);
}
