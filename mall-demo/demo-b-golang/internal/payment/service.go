package payment

import (
	"context"
	"fmt"
	"math/rand"
	"time"

	"github.com/google/uuid"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
)

type Service struct {
	repo *Repository
}

func NewService(repo *Repository) *Service {
	return &Service{repo: repo}
}

// ProcessPayment processes a payment with 80% success rate and 20% failure rate.
func (s *Service) ProcessPayment(ctx context.Context, orderID uint, amount float64) (*PaymentResponse, error) {
	// Create OTel span
	tracer := otel.Tracer("payment-svc")
	ctx, span := tracer.Start(ctx, "ProcessPayment")
	defer span.End()

	span.SetAttributes(
		attribute.Int64("payment.order_id", int64(orderID)),
		attribute.Float64("payment.amount", amount),
	)

	// Simulate processing delay
	time.Sleep(50 * time.Millisecond)

	// 80% success, 20% failure
	success := rand.Intn(100) < 80

	txID := uuid.New().String()
	status := "success"
	message := "payment processed"

	if !success {
		status = "failed"
		message = "payment declined (simulated)"
		span.SetAttributes(attribute.String("payment.status", "failed"))
	} else {
		span.SetAttributes(attribute.String("payment.status", "success"))
	}

	// Save to DB
	p := &Payment{
		OrderID:       orderID,
		Amount:        amount,
		Status:        status,
		TransactionID: txID,
	}
	if err := s.repo.Create(ctx, p); err != nil {
		return nil, fmt.Errorf("save payment: %w", err)
	}

	if !success {
		return nil, fmt.Errorf("payment declined: %s", message)
	}

	return &PaymentResponse{
		Success:       true,
		Message:       message,
		TransactionID: txID,
		Amount:        amount,
	}, nil
}

func (s *Service) GetByOrderID(ctx context.Context, orderID uint) (*Payment, error) {
	return s.repo.GetByOrderID(ctx, orderID)
}

func (s *Service) List(ctx context.Context, page, pageSize int) ([]Payment, int64, error) {
	if page < 1 {
		page = 1
	}
	if pageSize < 1 || pageSize > 100 {
		pageSize = 20
	}
	return s.repo.List(ctx, page, pageSize)
}

// GRPCProcessPayment implements the gRPC server interface.
func (s *Service) GRPCProcessPayment(ctx context.Context, req *PaymentRequest) (*PaymentResponse, error) {
	return s.ProcessPayment(ctx, uint(req.OrderID), req.Amount)
}
