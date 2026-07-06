package order

import "time"

type Order struct {
	ID            uint      `json:"id" gorm:"primaryKey"`
	UserID        uint      `json:"user_id" gorm:"index;not null"`
	ProductID     uint      `json:"product_id" gorm:"index;not null"`
	Quantity      int       `json:"quantity" gorm:"not null"`
	TotalPrice    float64   `json:"total_price" gorm:"not null"`
	Status        string    `json:"status" gorm:"size:20;default:'pending';index"`
	PaymentStatus string    `json:"payment_status" gorm:"size:20;default:'unpaid'"`
	CreatedAt     time.Time `json:"created_at"`
	UpdatedAt     time.Time `json:"updated_at"`
}

// OrderEvent is published to Kafka when an order is created.
type OrderEvent struct {
	OrderID    uint    `json:"order_id"`
	UserID     uint    `json:"user_id"`
	ProductID  uint    `json:"product_id"`
	Quantity   int     `json:"quantity"`
	TotalPrice float64 `json:"total_price"`
	Status     string  `json:"status"`
	Action     string  `json:"action"` // "created", "paid", "failed"
}

type CreateOrderReq struct {
	UserID    uint    `json:"user_id" binding:"required"`
	ProductID uint    `json:"product_id" binding:"required"`
	Quantity  int     `json:"quantity" binding:"required,min=1"`
	Price     float64 `json:"price" binding:"required,gt=0"`
}
