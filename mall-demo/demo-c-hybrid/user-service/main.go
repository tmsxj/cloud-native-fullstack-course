package main

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"os"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
	"gorm.io/driver/mysql"
	"gorm.io/gorm"
	"go.opentelemetry.io/contrib/instrumentation/github.com/gin-gonic/gin/otelgin"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
	"go.opentelemetry.io/otel/propagation"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	semconv "go.opentelemetry.io/otel/semconv/v1.21.0"
)

// User 用户模型
type User struct {
	ID        uint      `json:"id" gorm:"primaryKey"`
	Username  string    `json:"username" gorm:"size:50;uniqueIndex;not null"`
	Email     string    `json:"email" gorm:"size:100;not null"`
	Phone     string    `json:"phone" gorm:"size:20"`
	Status    string    `json:"status" gorm:"size:20;default:active"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

var db *gorm.DB

func main() {
	// 初始化数据库
	initDB()

	// 初始化OpenTelemetry
	ctx := context.Background()
	shutdown := initTracer(ctx)
	defer shutdown(ctx)

	r := gin.Default()
	r.Use(otelgin.Middleware("user-service"))

	// 健康检查
	r.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "UP", "service": "user-service"})
	})
	r.GET("/ready", func(c *gin.Context) {
		sqlDB, _ := db.DB()
		if err := sqlDB.Ping(); err != nil {
			c.JSON(http.StatusServiceUnavailable, gin.H{"status": "NOT READY", "error": err.Error()})
			return
		}
		c.JSON(http.StatusOK, gin.H{"status": "READY", "service": "user-service"})
	})

	// 用户API
	r.POST("/register", registerUser)
	r.GET("/users/:id", getUser)
	r.GET("/users", listUsers)

	port := getEnv("SERVER_PORT", "8080")
	log.Printf("User Service starting on port %s", port)
	if err := r.Run(":" + port); err != nil {
		log.Fatalf("Failed to start server: %v", err)
	}
}

func initDB() {
	dsn := fmt.Sprintf("%s:%s@tcp(%s:%s)/%s?charset=utf8mb4&parseTime=True&loc=Local",
		getEnv("DB_USERNAME", "root"),
		getEnv("DB_PASSWORD", "Harbor12345"),
		getEnv("DB_HOST", "192.168.1.61"),
		getEnv("DB_PORT", "3306"),
		getEnv("DB_NAME", "mall_user"),
	)

	var err error
	db, err = gorm.Open(mysql.Open(dsn), &gorm.Config{})
	if err != nil {
		log.Fatalf("Failed to connect to database: %v", err)
	}

	// 自动迁移
	db.AutoMigrate(&User{})
	log.Println("Database connected and migrated successfully")
}

func registerUser(c *gin.Context) {
	var user User
	if err := c.ShouldBindJSON(&user); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"code": 400, "message": "Invalid request: " + err.Error()})
		return
	}

	// 检查用户名是否已存在
	var existing User
	if result := db.Where("username = ?", user.Username).First(&existing); result.Error == nil {
		c.JSON(http.StatusConflict, gin.H{"code": 409, "message": "Username already exists"})
		return
	}

	if err := db.Create(&user).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"code": 500, "message": "Failed to create user"})
		return
	}

	c.JSON(http.StatusCreated, gin.H{
		"code":    201,
		"message": "User registered successfully",
		"data":    user,
	})
}

func getUser(c *gin.Context) {
	idStr := c.Param("id")
	id, err := strconv.ParseUint(idStr, 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"code": 400, "message": "Invalid user ID"})
		return
	}

	var user User
	if result := db.First(&user, id); result.Error != nil {
		c.JSON(http.StatusNotFound, gin.H{"code": 404, "message": "User not found"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"code": 200, "data": user})
}

func listUsers(c *gin.Context) {
	var users []User
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	size, _ := strconv.Atoi(c.DefaultQuery("size", "10"))

	offset := (page - 1) * size
	if result := db.Offset(offset).Limit(size).Find(&users); result.Error != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"code": 500, "message": "Failed to list users"})
		return
	}

	var total int64
	db.Model(&User{}).Count(&total)

	c.JSON(http.StatusOK, gin.H{
		"code":  200,
		"data":  users,
		"total": total,
		"page":  page,
		"size":  size,
	})
}

func initTracer(ctx context.Context) func(context.Context) error {
	otelEndpoint := getEnv("OTEL_EXPORTER_OTLP_ENDPOINT", "otel-collector.monitoring:4317")

	exporter, err := otlptracegrpc.New(ctx,
		otlptracegrpc.WithEndpoint(otelEndpoint),
		otlptracegrpc.WithInsecure(),
	)
	if err != nil {
		log.Printf("Warning: Failed to create OTel exporter: %v", err)
		return func(ctx context.Context) error { return nil }
	}

	tp := sdktrace.NewTracerProvider(
		sdktrace.WithBatcher(exporter),
		sdktrace.WithResource(resource.NewWithAttributes(
			semconv.SchemaURL,
			semconv.ServiceNameKey.String("user-service"),
			semconv.ServiceVersionKey.String("1.0.0"),
		)),
	)

	otel.SetTracerProvider(tp)
	otel.SetTextMapPropagator(propagation.NewCompositeTextMapPropagator(
		propagation.TraceContext{},
		propagation.Baggage{},
	))

	return tp.Shutdown
}

func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}
