package com.demo.user.controller;

import com.demo.user.entity.User;
import com.demo.user.service.UserService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.web.bind.annotation.*;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

@Slf4j
@RestController
@RequestMapping("/api/users")
@RequiredArgsConstructor
public class UserController {

    private final UserService userService;

    @PostMapping
    public Map<String, Object> register(@RequestBody Map<String, String> body) {
        log.info("Register request: {}", body.get("username"));
        User user = userService.register(
                body.get("username"),
                body.get("email"),
                body.get("phone"),
                body.get("password")
        );
        return success(user);
    }

    @GetMapping("/{id}")
    public Map<String, Object> getUser(@PathVariable Long id) {
        log.info("Get user request: {}", id);
        return success(userService.getUserById(id));
    }

    @GetMapping("/username/{username}")
    public Map<String, Object> getUserByUsername(@PathVariable String username) {
        log.info("Get user by username: {}", username);
        User user = userService.getUserByUsername(username);
        if (user == null) {
            return fail("User not found");
        }
        return success(user);
    }

    @GetMapping("/{id}/verify")
    public Map<String, Object> verifyUser(@PathVariable Long id) {
        log.info("Verify user request: {}", id);
        boolean valid = userService.verifyUser(id);
        Map<String, Object> result = new HashMap<>();
        result.put("userId", id);
        result.put("valid", valid);
        result.put("success", true);
        return result;
    }

    @GetMapping
    public Map<String, Object> listUsers() {
        log.info("List users request");
        List<User> users = userService.listUsers();
        return success(users);
    }

    @PutMapping("/{id}")
    public Map<String, Object> updateUser(@PathVariable Long id, @RequestBody User user) {
        log.info("Update user request: {}", id);
        user.setId(id);
        return success(userService.updateUser(user));
    }

    @DeleteMapping("/{id}")
    public Map<String, Object> deleteUser(@PathVariable Long id) {
        log.info("Delete user request: {}", id);
        userService.deleteUser(id);
        return success("User deleted");
    }

    @GetMapping("/health")
    public Map<String, Object> health() {
        Map<String, Object> health = new HashMap<>();
        health.put("status", "UP");
        health.put("service", "user-service");
        return health;
    }

    private Map<String, Object> success(Object data) {
        Map<String, Object> result = new HashMap<>();
        result.put("success", true);
        result.put("data", data);
        return result;
    }

    private Map<String, Object> fail(String message) {
        Map<String, Object> result = new HashMap<>();
        result.put("success", false);
        result.put("message", message);
        return result;
    }
}
