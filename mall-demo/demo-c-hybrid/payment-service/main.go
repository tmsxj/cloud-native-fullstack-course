package main

import (
	"context"
	"fmt"
	"log"
	"math/rand"
	"net/http"
	"os"
	"sync"
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

// Payment 支付记录
type Payment struct {
	ID            string    `json:"id"`
	OrderID       string    `json:"order_id"`
	Amount        float64   `json:"amount"`
	Method        string    `json:"method"`
	Status        string    `json:"status"`
	TransactionID string    `json:"transaction_id"`
	CreatedAt     time.Time `json:"created_at"`
}

var (
	payments   = make(map[string]Payment)
	paymentsMu sync.RWMutex
)

func main() {
	ctx := context.Background()
	shutdown := initTracer(ctx)
	defer shutdown(ctx)

	r := gin.Default()
	r.Use(otelgin.Middleware("payment-service"))

	r.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "UP", "service": "payment-service"})
	})
	r.GET("/ready", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "READY", "service": "payment-service"})
	})

	r.POST("/payments", createPayment)
	r.GET("/payments/:id", getPayment)

	port := getEnv("SERVER_PORT", "8080")
	log.Printf("Payment Service starting on port %s", port)
	if err := r.Run(":" + port); err != nil {
		log.Fatalf("Failed to start server: %v", err)
	}
}

type PaymentRequest struct {
	OrderID string  `json:"order_id" binding:"required"`
	Amount  float64 `json:"amount" binding:"required"`
	Method  string  `json:"method" binding:"required"`
}

func createPayment(c *gin.Context) {
	var req PaymentRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"code": 400, "message": "Invalid request: " + err.Error()})
		return
	}

	// 模拟支付处理延迟
	processingTime := time.Duration(rand.Intn(200)+50) * time.Millisecond
	time.Sleep(processingTime)

	// 10%概率模拟支付失败
	if rand.Float32() < 0.10 {
		log.Printf("Payment failed for order %s (simulated)", req.OrderID)
		c.JSON(http.StatusOK, gin.H{
			"code":    500,
			"message": "Payment processing failed",
			"data": gin.H{
				"order_id": req.OrderID,
				"status":   "failed",
				"reason":   "Insufficient balance or payment gateway timeout",
			},
		})
		return
	}

	payment := Payment{
		ID:            generateID(),
		OrderID:       req.OrderID,
		Amount:        req.Amount,
		Method:        req.Method,
		Status:        "completed",
		TransactionID: fmt.Sprintf("TXN%d%d", time.Now().UnixNano(), rand.Intn(1000)),
		CreatedAt:     time.Now(),
	}

	paymentsMu.Lock()
	payments[payment.ID] = payment
	paymentsMu.Unlock()

	log.Printf("Payment completed: %s for order %s, amount: %.2f", payment.ID, payment.OrderID, payment.Amount)

	c.JSON(http.StatusOK, gin.H{
		"code":    200,
		"message": "Payment successful",
		"data":    payment,
	})
}

func getPayment(c *gin.Context) {
	id := c.Param("id")

	paymentsMu.RLock()
	payment, exists := payments[id]
	paymentsMu.RUnlock()

	if !exists {
		c.JSON(http.StatusNotFound, gin.H{"code": 404, "message": "Payment not found"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"code": 200, "data": payment})
}

func generateID() string {
	return fmt.Sprintf("PAY%d", time.Now().UnixNano())
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
			semconv.ServiceNameKey.String("payment-service"),
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
