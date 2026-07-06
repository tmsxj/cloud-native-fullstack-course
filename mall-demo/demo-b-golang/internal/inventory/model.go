package inventory

import "time"

type Product struct {
	ID        uint      `json:"id" gorm:"primaryKey"`
	Name      string    `json:"name" gorm:"size:100;not null"`
	Price     float64   `json:"price" gorm:"not null"`
	Stock     int       `json:"stock" gorm:"default:0;not null"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

// gRPC request/response types (inline proto to avoid proto compilation dependency)
type DeductStockRequest struct {
	ProductId uint64 `json:"product_id"`
	Quantity  int64  `json:"quantity"`
}

type DeductStockResponse struct {
	Success bool   `json:"success"`
	Message string `json:"message"`
	Stock   int64  `json:"stock"`
}

type GetStockRequest struct {
	ProductId uint64 `json:"product_id"`
}

type GetStockResponse struct {
	ProductId uint64 `json:"product_id"`
	Stock     int64  `json:"stock"`
}

// InventoryServiceClient is the gRPC client interface.
type InventoryServiceClient interface {
	DeductStock(ctx context.Context, req *DeductStockRequest, opts ...interface{}) (*DeductStockResponse, error)
	GetStock(ctx context.Context, req *GetStockRequest, opts ...interface{}) (*GetStockResponse, error)
}

// InventoryServiceServer is the gRPC server interface.
type InventoryServiceServer interface {
	DeductStock(ctx context.Context, req *DeductStockRequest) (*DeductStockResponse, error)
	GetStock(ctx context.Context, req *GetStockRequest) (*GetStockResponse, error)
}

type CreateProductReq struct {
	Name  string  `json:"name" binding:"required"`
	Price float64 `json:"price" binding:"required,gt=0"`
	Stock int     `json:"stock" binding:"gte=0"`
}

type UpdateStockReq struct {
	Stock int `json:"stock" binding:"gte=0"`
}
