package com.demo.payment.mapper;

import com.demo.payment.entity.Payment;
import org.apache.ibatis.annotations.*;

import java.util.List;

@Mapper
public interface PaymentMapper {

    @Insert("INSERT INTO payments(payment_no, order_id, user_id, amount, method, status, remark, created_at, updated_at) " +
            "VALUES(#{paymentNo}, #{orderId}, #{userId}, #{amount}, #{method}, #{status}, #{remark}, NOW(), NOW())")
    @Options(useGeneratedKeys = true, keyProperty = "id")
    int insert(Payment payment);

    @Select("SELECT * FROM payments WHERE id = #{id}")
    @Results({
            @Result(property = "paymentNo", column = "payment_no"),
            @Result(property = "orderId", column = "order_id"),
            @Result(property = "userId", column = "user_id"),
            @Result(property = "createdAt", column = "created_at"),
            @Result(property = "updatedAt", column = "updated_at")
    })
    Payment findById(Long id);

    @Select("SELECT * FROM payments WHERE payment_no = #{paymentNo}")
    @Results({
            @Result(property = "paymentNo", column = "payment_no"),
            @Result(property = "orderId", column = "order_id"),
            @Result(property = "userId", column = "user_id"),
            @Result(property = "createdAt", column = "created_at"),
            @Result(property = "updatedAt", column = "updated_at")
    })
    Payment findByPaymentNo(String paymentNo);

    @Select("SELECT * FROM payments WHERE order_id = #{orderId}")
    @Results({
            @Result(property = "paymentNo", column = "payment_no"),
            @Result(property = "orderId", column = "order_id"),
            @Result(property = "userId", column = "user_id"),
            @Result(property = "createdAt", column = "created_at"),
            @Result(property = "updatedAt", column = "updated_at")
    })
    List<Payment> findByOrderId(String orderId);

    @Select("SELECT * FROM payments")
    @Results({
            @Result(property = "paymentNo", column = "payment_no"),
            @Result(property = "orderId", column = "order_id"),
            @Result(property = "userId", column = "user_id"),
            @Result(property = "createdAt", column = "created_at"),
            @Result(property = "updatedAt", column = "updated_at")
    })
    List<Payment> findAll();

    @Update("UPDATE payments SET status=#{status}, remark=#{remark}, updated_at=NOW() WHERE id=#{id}")
    int updateStatus(Payment payment);
}
