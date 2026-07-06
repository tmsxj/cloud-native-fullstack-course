package notification

import (
	"context"
	"fmt"
	"log"
	"time"

	kafkapkg "mall-demo/internal/pkg/kafka"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
)

type Service struct {
	repo *Repository
}

func NewService(repo *Repository) *Service {
	return &Service{repo: repo}
}

// ProcessOrderEvent processes an order event and sends a notification.
func (s *Service) ProcessOrderEvent(ctx context.Context, event *OrderEvent) error {
	tracer := otel.Tracer("notification-svc")
	ctx, span := tracer.Start(ctx, "ProcessOrderEvent")
	defer span.End()

	span.SetAttributes(
		attribute.Int64("notification.order_id", int64(event.OrderID)),
		attribute.Int64("notification.user_id", int64(event.UserID)),
		attribute.String("notification.action", event.Action),
	)

	var notifType, title, content string

	switch event.Action {
	case "created":
		notifType = "order_confirmation"
		title = fmt.Sprintf("Order #%d Confirmed", event.OrderID)
		content = fmt.Sprintf("Your order #%d has been confirmed. Total: $%.2f (%d items). Thank you for your purchase!",
			event.OrderID, event.TotalPrice, event.Quantity)
	case "failed":
		notifType = "order_failed"
		title = fmt.Sprintf("Order #%d Failed", event.OrderID)
		content = fmt.Sprintf("Your order #%d could not be processed. Payment failed. Please try again or contact support.",
			event.OrderID)
	default:
		notifType = "order_update"
		title = fmt.Sprintf("Order #%d Update", event.OrderID)
		content = fmt.Sprintf("Your order #%d status: %s", event.OrderID, event.Status)
	}

	notif := &Notification{
		OrderID: event.OrderID,
		UserID:  event.UserID,
		Type:    notifType,
		Title:   title,
		Content: content,
		Status:  "sent",
	}

	if err := s.repo.Create(ctx, notif); err != nil {
		return fmt.Errorf("save notification: %w", err)
	}

	// Simulate sending notification (email/SMS)
	log.Printf("[notification-svc] notification sent: type=%s order=%d user=%d title=%s",
		notifType, event.OrderID, event.UserID, title)

	return nil
}

func (s *Service) List(ctx context.Context, page, pageSize int) ([]Notification, int64, error) {
	if page < 1 {
		page = 1
	}
	if pageSize < 1 || pageSize > 100 {
		pageSize = 20
	}
	return s.repo.List(ctx, page, pageSize)
}

func (s *Service) ListByUser(ctx context.Context, userID uint, page, pageSize int) ([]Notification, int64, error) {
	if page < 1 {
		page = 1
	}
	if pageSize < 1 || pageSize > 100 {
		pageSize = 20
	}
	return s.repo.ListByUser(ctx, userID, page, pageSize)
}

// StartKafkaConsumer starts the Kafka consumer for order events.
func StartKafkaConsumer(svc *Service, brokers []string) {
	consumer := kafkapkg.NewConsumer(brokers, "order-events", "notification-svc-group")

	handler := func(ctx context.Context, key string, value []byte) error {
		log.Printf("[notification-svc] received event: key=%s", key)

		var event OrderEvent
		if err := kafkapkg.DecodeJSON(value, &event); err != nil {
			return fmt.Errorf("unmarshal: %w", err)
		}

		// Add a small delay to simulate processing
		time.Sleep(100 * time.Millisecond)

		return svc.ProcessOrderEvent(ctx, &event)
	}

	log.Println("[notification-svc] starting kafka consumer...")
	if err := consumer.Consume(context.Background(), handler); err != nil {
		log.Printf("[notification-svc] kafka consumer error: %v", err)
	}
}
