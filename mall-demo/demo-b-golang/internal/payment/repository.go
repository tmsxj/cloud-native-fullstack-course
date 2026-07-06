package payment

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
	r.db.AutoMigrate(&Payment{})
}

func (r *Repository) Create(ctx context.Context, p *Payment) error {
	return r.db.WithContext(ctx).Create(p).Error
}

func (r *Repository) GetByOrderID(ctx context.Context, orderID uint) (*Payment, error) {
	var p Payment
	if err := r.db.WithContext(ctx).Where("order_id = ?", orderID).First(&p).Error; err != nil {
		return nil, fmt.Errorf("payment not found: %w", err)
	}
	return &p, nil
}

func (r *Repository) List(ctx context.Context, page, pageSize int) ([]Payment, int64, error) {
	var payments []Payment
	var total int64

	r.db.WithContext(ctx).Model(&Payment{}).Count(&total)

	offset := (page - 1) * pageSize
	err := r.db.WithContext(ctx).Order("id desc").Offset(offset).Limit(pageSize).Find(&payments).Error
	return payments, total, err
}
