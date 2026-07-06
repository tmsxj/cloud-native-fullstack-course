package order

import (
	"context"
	"fmt"
	"log"

	kafkapkg "mall-demo/internal/pkg/kafka"
)

// gRPC client interfaces - we define them here so order-svc can call inventory and payment
type InventoryClient interface {
	DeductStock(ctx context.Context, productID uint, quantity int) error
}

type PaymentClient interface {
	ProcessPayment(ctx context.Context, orderID uint, amount float64) error
}

type Service struct {
	repo   *Repository
	prod   *kafkapkg.Producer
	invCli InventoryClient
	payCli PaymentClient
}

func NewService(repo *Repository, prod *kafkapkg.Producer, invCli InventoryClient, payCli PaymentClient) *Service {
	return &Service{
		repo:   repo,
		prod:   prod,
		invCli: invCli,
		payCli: payCli,
	}
}

func (s *Service) CreateOrder(ctx context.Context, req *CreateOrderReq) (*Order, error) {
	totalPrice := req.Price * float64(req.Quantity)

	// 1. Create order record
	o := &Order{
		UserID:     req.UserID,
		ProductID:  req.ProductID,
		Quantity:   req.Quantity,
		TotalPrice: totalPrice,
		Status:     "pending",
	}
	if err := s.repo.Create(ctx, o); err != nil {
		return nil, fmt.Errorf("create order: %w", err)
	}

	// 2. Deduct inventory via gRPC
	if err := s.invCli.DeductStock(ctx, req.ProductID, req.Quantity); err != nil {
		_ = s.repo.UpdateStatus(ctx, o.ID, "cancelled", "failed")
		return nil, fmt.Errorf("deduct inventory: %w", err)
	}

	// 3. Process payment via gRPC
	if err := s.payCli.ProcessPayment(ctx, o.ID, totalPrice); err != nil {
		log.Printf("[order-svc] payment failed for order %d: %v", o.ID, err)
		_ = s.repo.UpdateStatus(ctx, o.ID, "payment_failed", "failed")

		// Publish failed event
		_ = s.prod.Publish(ctx, "order-events",
			fmt.Sprintf("order-%d", o.ID),
			OrderEvent{
				OrderID: o.ID, UserID: o.UserID, ProductID: o.ProductID,
				Quantity: req.Quantity, TotalPrice: totalPrice,
				Status: "payment_failed", Action: "failed",
			},
		)
		return o, nil
	}

	// 4. Update order status
	_ = s.repo.UpdateStatus(ctx, o.ID, "paid", "paid")

	// 5. Publish order event to Kafka
	if err := s.prod.Publish(ctx, "order-events",
		fmt.Sprintf("order-%d", o.ID),
		OrderEvent{
			OrderID: o.ID, UserID: o.UserID, ProductID: o.ProductID,
			Quantity: req.Quantity, TotalPrice: totalPrice,
			Status: "paid", Action: "created",
		},
	); err != nil {
		log.Printf("[order-svc] publish event failed: %v", err)
	}

	return o, nil
}

func (s *Service) GetByID(ctx context.Context, id uint) (*Order, error) {
	return s.repo.GetByID(ctx, id)
}

func (s *Service) ListByUser(ctx context.Context, userID uint, page, pageSize int) ([]Order, int64, error) {
	if page < 1 {
		page = 1
	}
	if pageSize < 1 || pageSize > 100 {
		pageSize = 20
	}
	return s.repo.ListByUser(ctx, userID, page, pageSize)
}
