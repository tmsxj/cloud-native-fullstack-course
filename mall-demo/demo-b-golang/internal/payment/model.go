package payment

import "time"

type Payment struct {
	ID            uint      `json:"id" gorm:"primaryKey"`
	OrderID       uint      `json:"order_id" gorm:"uniqueIndex;not null"`
	Amount        float64   `json:"amount" gorm:"not null"`
	Status        string    `json:"status" gorm:"size:20;default:'pending'"`
	TransactionID string    `json:"transaction_id" gorm:"size:64"`
	CreatedAt     time.Time `json:"created_at"`
	UpdatedAt     time.Time `json:"updated_at"`
}

// gRPC request/response types
type PaymentRequest struct {
	OrderID uint64  `json:"order_id"`
	Amount  float64 `json:"amount"`
}

type PaymentResponse struct {
	Success       bool    `json:"success"`
	Message       string  `json:"message"`
	TransactionID string  `json:"transaction_id"`
	Amount        float64 `json:"amount"`
}

// PaymentServiceClient is the gRPC client interface.
type PaymentServiceClient interface {
	ProcessPayment(ctx context.Context, req *PaymentRequest, opts ...interface{}) (*PaymentResponse, error)
}

// PaymentServiceServer is the gRPC server interface.
type PaymentServiceServer interface {
	ProcessPayment(ctx context.Context, req *PaymentRequest) (*PaymentResponse, error)
}
