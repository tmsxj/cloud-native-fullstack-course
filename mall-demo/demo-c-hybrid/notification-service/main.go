package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"math/rand"
	"net/http"
	"os"
	"sync"
	"time"

	"github.com/IBM/sarama"
	"github.com/gin-gonic/gin"
	"go.opentelemetry.io/contrib/instrumentation/github.com/gin-gonic/gin/otelgin"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
	"go.opentelemetry.io/otel/propagation"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	semconv "go.opentelemetry.io/otel/semconv/v1.21.0"
)

// Notification 通知记录
type Notification struct {
	ID        string    `json:"id"`
	Type      string    `json:"type"`
	OrderID   string    `json:"order_id"`
	UserID    string    `json:"user_id"`
	Title     string    `json:"title"`
	Content   string    `json:"content"`
	Status    string    `json:"status"`
	CreatedAt time.Time `json:"created_at"`
}

// OrderEvent 订单事件 (Kafka消息)
type OrderEvent struct {
	EventType string  `json:"event_type"`
	OrderID   string  `json:"order_id"`
	UserID    string  `json:"user_id"`
	Amount    float64 `json:"amount"`
	Status    string  `json:"status"`
}

var (
	notifications   = make(map[string]Notification)
	notificationsMu sync.RWMutex
	stats = struct {
		TotalSent     int64
		TotalFailed   int64
		mu            sync.Mutex
	}{}
)

func main() {
	ctx := context.Background()
	shutdown := initTracer(ctx)
	defer shutdown(ctx)

	// 启动Kafka消费者
	go startKafkaConsumer()

	r := gin.Default()
	r.Use(otelgin.Middleware("notification-service"))

	r.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "UP", "service": "notification-service"})
	})
	r.GET("/ready", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "READY", "service": "notification-service"})
	})

	r.GET("/notifications", listNotifications)
	r.GET("/notifications/:id", getNotification)
	r.GET("/stats", getStats)

	port := getEnv("SERVER_PORT", "8080")
	log.Printf("Notification Service starting on port %s", port)
	if err := r.Run(":" + port); err != nil {
		log.Fatalf("Failed to start server: %v", err)
	}
}

func startKafkaConsumer() {
	brokers := []string{getEnv("KAFKA_BROKERS", "192.168.1.61:9092")}
	topic := getEnv("KAFKA_TOPIC", "order-events")

	config := sarama.NewConfig()
	config.Consumer.Group.Rebalance.Strategy = sarama.NewBalanceStrategyRoundRobin()
	config.Consumer.Offsets.Initial = sarama.OffsetNewest

	consumer, err := sarama.NewConsumerGroup(brokers, "notification-service-group", config)
	if err != nil {
		log.Printf("Warning: Failed to create Kafka consumer: %v", err)
		return
	}
	defer consumer.Close()

	handler := &NotificationHandler{}

	for {
		if err := consumer.Consume(context.Background(), []string{topic}, handler); err != nil {
			log.Printf("Kafka consumer error: %v", err)
			time.Sleep(5 * time.Second)
		}
	}
}

// NotificationHandler Kafka消费者处理器
type NotificationHandler struct{}

func (h *NotificationHandler) Setup(sarama.ConsumerGroupSession) error   { return nil }
func (h *NotificationHandler) Cleanup(sarama.ConsumerGroupSession) error { return nil }

func (h *NotificationHandler) ConsumeClaim(session sarama.ConsumerGroupSession, claim sarama.ConsumerGroupClaim) error {
	for message := range claim.Messages() {
		log.Printf("Received Kafka message: topic=%s partition=%d offset=%d",
			message.Topic, message.Partition, message.Offset)

		var event OrderEvent
		if err := json.Unmarshal(message.Value, &event); err != nil {
			log.Printf("Failed to unmarshal message: %v", err)
			continue
		}

		// 处理通知
		processNotification(event)
		session.MarkMessage(message, "")
	}
	return nil
}

func processNotification(event OrderEvent) {
	notification := Notification{
		ID:        fmt.Sprintf("NOTIF%d", time.Now().UnixNano()),
		OrderID:   event.OrderID,
		UserID:    event.UserID,
		CreatedAt: time.Now(),
	}

	switch event.EventType {
	case "ORDER_CREATED":
		notification.Type = "order_confirmation"
		notification.Title = "Order Created"
		notification.Content = fmt.Sprintf("Your order %s has been created. Amount: %.2f", event.OrderID, event.Amount)
	case "ORDER_PAID":
		notification.Type = "payment_success"
		notification.Title = "Payment Successful"
		notification.Content = fmt.Sprintf("Payment for order %s has been processed successfully.", event.OrderID)
	case "ORDER_CANCELLED":
		notification.Type = "order_cancelled"
		notification.Title = "Order Cancelled"
		notification.Content = fmt.Sprintf("Your order %s has been cancelled.", event.OrderID)
	case "PAYMENT_FAILED":
		notification.Type = "payment_failed"
		notification.Title = "Payment Failed"
		notification.Content = fmt.Sprintf("Payment for order %s failed. Please try again.", event.OrderID)
	default:
		notification.Type = "system"
		notification.Title = "System Notification"
		notification.Content = fmt.Sprintf("Update on order %s: %s", event.OrderID, event.EventType)
	}

	// 5%概率模拟发送失败
	if rand.Float32() < 0.05 {
		notification.Status = "failed"
		stats.mu.Lock()
		stats.TotalFailed++
		stats.mu.Unlock()
		log.Printf("Notification send failed: %s for order %s", notification.ID, notification.OrderID)
	} else {
		notification.Status = "sent"
		stats.mu.Lock()
		stats.TotalSent++
		stats.mu.Unlock()
		log.Printf("Notification sent: %s [%s] for order %s", notification.ID, notification.Type, notification.OrderID)
	}

	notificationsMu.Lock()
	notifications[notification.ID] = notification
	notificationsMu.Unlock()
}

func listNotifications(c *gin.Context) {
	notificationsMu.RLock()
	defer notificationsMu.RUnlock()

	result := make([]Notification, 0, len(notifications))
	for _, n := range notifications {
		result = append(result, n)
	}

	c.JSON(http.StatusOK, gin.H{
		"code": 200,
		"data": result,
	})
}

func getNotification(c *gin.Context) {
	id := c.Param("id")

	notificationsMu.RLock()
	notification, exists := notifications[id]
	notificationsMu.RUnlock()

	if !exists {
		c.JSON(http.StatusNotFound, gin.H{"code": 404, "message": "Notification not found"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"code": 200, "data": notification})
}

func getStats(c *gin.Context) {
	stats.mu.Lock()
	defer stats.mu.Unlock()

	c.JSON(http.StatusOK, gin.H{
		"code": 200,
		"data": gin.H{
			"total_sent":   stats.TotalSent,
			"total_failed": stats.TotalFailed,
		},
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
			semconv.ServiceNameKey.String("notification-service"),
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
