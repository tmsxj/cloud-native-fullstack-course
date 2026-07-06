package inventory

import (
	"context"
	"fmt"
)

type Service struct {
	repo *Repository
}

func NewService(repo *Repository) *Service {
	return &Service{repo: repo}
}

func (s *Service) CreateProduct(ctx context.Context, req *CreateProductReq) (*Product, error) {
	p := &Product{
		Name:  req.Name,
		Price: req.Price,
		Stock: req.Stock,
	}
	if err := s.repo.Create(ctx, p); err != nil {
		return nil, fmt.Errorf("create product: %w", err)
	}
	return p, nil
}

func (s *Service) GetByID(ctx context.Context, id uint) (*Product, error) {
	return s.repo.GetByID(ctx, id)
}

func (s *Service) DeductStock(ctx context.Context, productID uint, quantity int) (int, error) {
	return s.repo.DeductStock(ctx, productID, quantity)
}

func (s *Service) UpdateStock(ctx context.Context, productID uint, stock int) error {
	return s.repo.UpdateStock(ctx, productID, stock)
}

func (s *Service) List(ctx context.Context, page, pageSize int) ([]Product, int64, error) {
	if page < 1 {
		page = 1
	}
	if pageSize < 1 || pageSize > 100 {
		pageSize = 20
	}
	return s.repo.List(ctx, page, pageSize)
}

// gRPC server implementation
func (s *Service) GRPCDeductStock(ctx context.Context, req *DeductStockRequest) (*DeductStockResponse, error) {
	stock, err := s.DeductStock(ctx, uint(req.ProductId), int(req.Quantity))
	if err != nil {
		return &DeductStockResponse{
			Success: false,
			Message: err.Error(),
		}, nil
	}
	return &DeductStockResponse{
		Success: true,
		Message: "stock deducted",
		Stock:   int64(stock),
	}, nil
}

func (s *Service) GRPCGetStock(ctx context.Context, req *GetStockRequest) (*GetStockResponse, error) {
	stock, err := s.repo.GetStock(ctx, uint(req.ProductId))
	if err != nil {
		return nil, err
	}
	return &GetStockResponse{
		ProductId: req.ProductId,
		Stock:     int64(stock),
	}, nil
}
