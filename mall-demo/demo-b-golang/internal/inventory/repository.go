package inventory

import (
	"context"
	"fmt"

	"gorm.io/gorm"
)

type Repository struct {
	db *gorm.DB
}

func NewRepository(db *gorm.DB) *Repository {
	return &Repository{db: db}
}

func (r *Repository) AutoMigrate() {
	r.db.AutoMigrate(&Product{})
}

func (r *Repository) Create(ctx context.Context, p *Product) error {
	return r.db.WithContext(ctx).Create(p).Error
}

func (r *Repository) GetByID(ctx context.Context, id uint) (*Product, error) {
	var p Product
	if err := r.db.WithContext(ctx).First(&p, id).Error; err != nil {
		return nil, fmt.Errorf("product not found: %w", err)
	}
	return &p, nil
}

func (r *Repository) GetStock(ctx context.Context, productID uint) (int, error) {
	var p Product
	if err := r.db.WithContext(ctx).Select("stock").First(&p, productID).Error; err != nil {
		return 0, fmt.Errorf("product not found: %w", err)
	}
	return p.Stock, nil
}

func (r *Repository) DeductStock(ctx context.Context, productID uint, quantity int) (int, error) {
	result := r.db.WithContext(ctx).
		Model(&Product{}).
		Where("id = ? AND stock >= ?", productID, quantity).
		Update("stock", gorm.Expr("stock - ?", quantity))

	if result.Error != nil {
		return 0, result.Error
	}
	if result.RowsAffected == 0 {
		return 0, fmt.Errorf("insufficient stock for product %d", productID)
	}

	var p Product
	r.db.WithContext(ctx).Select("stock").First(&p, productID)
	return p.Stock, nil
}

func (r *Repository) UpdateStock(ctx context.Context, productID uint, stock int) error {
	return r.db.WithContext(ctx).Model(&Product{}).Where("id = ?", productID).Update("stock", stock).Error
}

func (r *Repository) List(ctx context.Context, page, pageSize int) ([]Product, int64, error) {
	var products []Product
	var total int64

	r.db.WithContext(ctx).Model(&Product{}).Count(&total)

	offset := (page - 1) * pageSize
	err := r.db.WithContext(ctx).Order("id desc").Offset(offset).Limit(pageSize).Find(&products).Error
	return products, total, err
}
