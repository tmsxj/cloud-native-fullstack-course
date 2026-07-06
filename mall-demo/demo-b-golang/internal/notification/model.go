package notification

import "time"

type Notification struct {
	ID        uint      `json:"id" gorm:"primaryKey"`
	OrderID   uint      `json:"order_id" gorm:"index"`
	UserID    uint      `json:"user_id" gorm:"index"`
	Type      string    `json:"type" gorm:"size:30"`
	Title     string    `json:"title" gorm:"size:200"`
	Content   string    `json:"content" gorm:"type:text"`
	Status    string    `json:"status" gorm:"size:20;default:'sent'"`
	CreatedAt time.Time `json:"created_at"`
}

// OrderEvent represents the event consumed from Kafka.
type OrderEvent struct {
	OrderID    uint    `json:"order_id"`
	UserID     uint    `json:"user_id"`
	ProductID  uint    `json:"product_id"`
	Quantity   int     `json:"quantity"`
	TotalPrice float64 `json:"total_price"`
	Status     string  `json:"status"`
	Action     string  `json:"action"`
}
