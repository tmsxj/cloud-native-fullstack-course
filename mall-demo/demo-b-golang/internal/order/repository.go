package order

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
	r.db.AutoMigrate(&Order{})
}

func (r *Repository) Create(ctx context.Context, o *Order) error {
	return r.db.WithContext(ctx).Create(o).Error
}

func (r *Repository) GetByID(ctx context.Context, id uint) (*Order, error) {
	var o Order
	if err := r.db.WithContext(ctx).First(&o, id).Error; err != nil {
		return nil, fmt.Errorf("order not found: %w", err)
	}
	return &o, nil
}

func (r *Repository) UpdateStatus(ctx context.Context, id uint, status, paymentStatus string) error {
	updates := map[string]interface{}{"status": status}
	if paymentStatus != "" {
		updates["payment_status"] = paymentStatus
	}
	return r.db.WithContext(ctx).Model(&Order{}).Where("id = ?", id).Updates(updates).Error
}

func (r *Repository) ListByUser(ctx context.Context, userID uint, page, pageSize int) ([]Order, int64, error) {
	var orders []Order
	var total int64

	r.db.WithContext(ctx).Model(&Order{}).Where("user_id = ?", userID).Count(&total)

	offset := (page - 1) * pageSize
	err := r.db.WithContext(ctx).
		Where("user_id = ?", userID).
		Order("id desc").
		Offset(offset).Limit(pageSize).
		Find(&orders).Error
	return orders, total, err
}
