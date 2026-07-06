package com.demo.inventory.mapper;

import com.demo.inventory.entity.Inventory;
import org.apache.ibatis.annotations.*;

import java.util.List;

@Mapper
public interface InventoryMapper {

    @Insert("INSERT INTO inventory(product_id, product_name, stock, locked_stock, version, created_at, updated_at) " +
            "VALUES(#{productId}, #{productName}, #{stock}, 0, 1, NOW(), NOW())")
    @Options(useGeneratedKeys = true, keyProperty = "id")
    int insert(Inventory inventory);

    @Select("SELECT * FROM inventory WHERE product_id = #{productId}")
    @Results({
            @Result(property = "productId", column = "product_id"),
            @Result(property = "productName", column = "product_name"),
            @Result(property = "lockedStock", column = "locked_stock"),
            @Result(property = "createdAt", column = "created_at"),
            @Result(property = "updatedAt", column = "updated_at")
    })
    Inventory findByProductId(Long productId);

    @Select("SELECT * FROM inventory WHERE id = #{id}")
    @Results({
            @Result(property = "productId", column = "product_id"),
            @Result(property = "productName", column = "product_name"),
            @Result(property = "lockedStock", column = "locked_stock"),
            @Result(property = "createdAt", column = "created_at"),
            @Result(property = "updatedAt", column = "updated_at")
    })
    Inventory findById(Long id);

    @Select("SELECT * FROM inventory")
    @Results({
            @Result(property = "productId", column = "product_id"),
            @Result(property = "productName", column = "product_name"),
            @Result(property = "lockedStock", column = "locked_stock"),
            @Result(property = "createdAt", column = "created_at"),
            @Result(property = "updatedAt", column = "updated_at")
    })
    List<Inventory> findAll();

    @Update("UPDATE inventory SET stock = stock - #{quantity}, locked_stock = locked_stock + #{quantity}, " +
            "version = version + 1, updated_at = NOW() " +
            "WHERE product_id = #{productId} AND stock >= #{quantity}")
    int deductStock(@Param("productId") Long productId, @Param("quantity") Integer quantity);

    @Update("UPDATE inventory SET stock = stock + #{quantity}, locked_stock = locked_stock - #{quantity}, " +
            "version = version + 1, updated_at = NOW() " +
            "WHERE product_id = #{productId} AND locked_stock >= #{quantity}")
    int restoreStock(@Param("productId") Long productId, @Param("quantity") Integer quantity);

    @Update("UPDATE inventory SET stock = stock + #{quantity}, version = version + 1, updated_at = NOW() " +
            "WHERE product_id = #{productId}")
    int addStock(@Param("productId") Long productId, @Param("quantity") Integer quantity);
}
