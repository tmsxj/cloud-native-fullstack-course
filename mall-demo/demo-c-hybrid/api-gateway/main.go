package main

import (
	"context"
	"fmt"
	"log"
	"math/rand"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"go.opentelemetry.io/contrib/instrumentation/github.com/gin-gonic/gin/otelgin"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
	"go.opentelemetry.io/otel/propagation"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	semconv "go.opentelemetry.io/otel/semconv/v1.21.0"
)

var (
	userServiceURL      string
	orderServiceURL     string
	paymentServiceURL   string
	inventoryServiceURL string
)

func main() {
	// 初始化环境变量
	userServiceURL = getEnv("USER_SERVICE_URL", "http://user-service:8080")
	orderServiceURL = getEnv("ORDER_SERVICE_URL", "http://order-service:8080")
	paymentServiceURL = getEnv("PAYMENT_SERVICE_URL", "http://payment-service:8080")
	inventoryServiceURL = getEnv("INVENTORY_SERVICE_URL", "http://inventory-service:8080")

	// 初始化OpenTelemetry
	ctx := context.Background()
	shutdown := initTracer(ctx)
	defer shutdown(ctx)

	r := gin.Default()

	// OTel中间件
	r.Use(otelgin.Middleware("api-gateway"))

	// 健康检查
	r.GET("/health", healthCheck)
	r.GET("/ready", readyCheck)

	// 用户路由 -> user-service (Go)
	user := r.Group("/api/v1/users")
	{
		user.POST("/register", proxyTo(userServiceURL))
		user.GET("/:id", proxyTo(userServiceURL))
		user.GET("/", proxyTo(userServiceURL))
	}

	// 订单路由 -> order-service (Spring Boot)
	orders := r.Group("/api/v1/orders")
	{
		orders.POST("/", proxyTo(orderServiceURL))
		orders.GET("/:id", proxyTo(orderServiceURL))
		orders.GET("/", proxyTo(orderServiceURL))
		orders.POST("/:id/pay", proxyTo(orderServiceURL))
		orders.POST("/:id/cancel", proxyTo(orderServiceURL))
	}

	// 库存路由 -> inventory-service (Spring Boot)
	inventory := r.Group("/api/v1/inventory")
	{
		inventory.GET("/product/:productId", proxyTo(inventoryServiceURL))
		inventory.POST("/deduct", proxyTo(inventoryServiceURL))
		inventory.POST("/restore", proxyTo(inventoryServiceURL))
	}

	// 支付路由 -> payment-service (Go)
	payment := r.Group("/api/v1/payments")
	{
		payment.POST("/", proxyTo(paymentServiceURL))
		payment.GET("/:id", proxyTo(paymentServiceURL))
	}

	// 指标端点
	r.GET("/metrics", metricsHandler)

	port := getEnv("SERVER_PORT", "8080")
	log.Printf("API Gateway starting on port %s", port)
	log.Printf("  User Service:      %s", userServiceURL)
	log.Printf("  Order Service:     %s", orderServiceURL)
	log.Printf("  Payment Service:   %s", paymentServiceURL)
	log.Printf("  Inventory Service: %s", inventoryServiceURL)

	if err := r.Run(":" + port); err != nil {
		log.Fatalf("Failed to start server: %v", err)
	}
}

func proxyTo(targetURL string) gin.HandlerFunc {
	target, err := url.Parse(targetURL)
	if err != nil {
		log.Fatalf("Invalid target URL %s: %v", targetURL, err)
	}

	proxy := httputil.NewSingleHostReverseProxy(target)
	originalDirector := proxy.Director

	proxy.Director = func(req *http.Request) {
		originalDirector(req)
		// 保留原始请求头
		req.Header.Set("X-Forwarded-Host", req.Host)
		req.Header.Set("X-Forwarded-Proto", "http")
		// 注入追踪头
		otel.GetTextMapPropagator().Inject(req.Context(), propagation.HeaderCarrier(req.Header))
	}

	proxy.ErrorHandler = func(w http.ResponseWriter, r *http.Request, err error) {
		log.Printf("Proxy error: %v", err)
		w.WriteHeader(http.StatusBadGateway)
		w.Write([]byte(fmt.Sprintf(`{"code":502,"message":"Service unavailable: %s"}`, err.Error())))
	}

	// 自定义传输以支持超时
	proxy.Transport = &http.Transport{
		ResponseHeaderTimeout: 10 * time.Second,
	}

	return func(c *gin.Context) {
		// 重写路径：去掉gateway前缀
		originalPath := c.Request.URL.Path
		c.Request.URL.Path = strings.TrimPrefix(originalPath, "/api/v1")

		// 模拟偶尔延迟（用于演示）
		if rand.Float32() < 0.05 {
			delay := time.Duration(rand.Intn(500)+100) * time.Millisecond
			log.Printf("Simulating delay %v for request %s", delay, originalPath)
			time.Sleep(delay)
		}

		proxy.ServeHTTP(c.Writer, c.Request)
	}
}

func healthCheck(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{
		"status":  "UP",
		"service": "api-gateway",
		"runtime": "Go",
	})
}

func readyCheck(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{
		"status":  "READY",
		"service": "api-gateway",
	})
}

func metricsHandler(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{
		"service":       "api-gateway",
		"runtime":       "Go",
		"uptime_seconds": time.Since(time.Now()).Seconds(),
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
			semconv.ServiceNameKey.String("api-gateway"),
			semconv.ServiceVersionKey.String("1.0.0"),
			semconv.DeploymentEnvironmentKey.String(getEnv("DEPLOY_ENV", "production")),
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
