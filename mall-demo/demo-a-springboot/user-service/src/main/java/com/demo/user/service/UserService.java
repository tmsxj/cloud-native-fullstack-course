package com.demo.user.service;

import com.demo.user.entity.User;
import com.demo.user.mapper.UserMapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.cache.annotation.CacheEvict;
import org.springframework.cache.annotation.CachePut;
import org.springframework.cache.annotation.Cacheable;
import org.springframework.stereotype.Service;

import java.util.List;

@Slf4j
@Service
@RequiredArgsConstructor
public class UserService {

    private final UserMapper userMapper;

    /**
     * Register a new user
     */
    public User register(String username, String email, String phone, String password) {
        log.info("Registering new user: {}", username);
        User existing = userMapper.findByUsername(username);
        if (existing != null) {
            throw new RuntimeException("Username already exists: " + username);
        }
        User user = new User();
        user.setUsername(username);
        user.setEmail(email);
        user.setPhone(phone);
        user.setPassword(password);
        user.setStatus(1);
        userMapper.insert(user);
        log.info("User registered successfully with id: {}", user.getId());
        return user;
    }

    /**
     * Get user by ID with Redis cache
     */
    @Cacheable(value = "user", key = "#id")
    public User getUserById(Long id) {
        log.info("Fetching user from DB, id: {}", id);
        User user = userMapper.findById(id);
        if (user == null) {
            throw new RuntimeException("User not found: " + id);
        }
        return user;
    }

    /**
     * Get user by username
     */
    public User getUserByUsername(String username) {
        log.info("Fetching user by username: {}", username);
        return userMapper.findByUsername(username);
    }

    /**
     * Verify user exists (used by order-service)
     */
    public boolean verifyUser(Long userId) {
        User user = userMapper.findById(userId);
        boolean valid = user != null && user.getStatus() == 1;
        log.info("User verification - userId: {}, valid: {}", userId, valid);
        return valid;
    }

    /**
     * List all users
     */
    public List<User> listUsers() {
        log.info("Listing all users");
        return userMapper.findAll();
    }

    /**
     * Update user info
     */
    @CachePut(value = "user", key = "#user.id")
    public User updateUser(User user) {
        log.info("Updating user: {}", user.getId());
        userMapper.update(user);
        return userMapper.findById(user.getId());
    }

    /**
     * Delete user
     */
    @CacheEvict(value = "user", key = "#id")
    public void deleteUser(Long id) {
        log.info("Deleting user: {}", id);
        userMapper.deleteById(id);
    }
}
