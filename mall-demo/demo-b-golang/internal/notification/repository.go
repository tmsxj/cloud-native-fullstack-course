package notification

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
	r.db.AutoMigrate(&Notification{})
}

func (r *Repository) Create(ctx context.Context, n *Notification) error {
	return r.db.WithContext(ctx).Create(n).Error
}

func (r *Repository) List(ctx context.Context, page, pageSize int) ([]Notification, int64, error) {
	var notifications []Notification
	var total int64

	r.db.WithContext(ctx).Model(&Notification{}).Count(&total)

	offset := (page - 1) * pageSize
	err := r.db.WithContext(ctx).Order("id desc").Offset(offset).Limit(pageSize).Find(&notifications).Error
	return notifications, total, err
}

func (r *Repository) ListByUser(ctx context.Context, userID uint, page, pageSize int) ([]Notification, int64, error) {
	var notifications []Notification
	var total int64

	r.db.WithContext(ctx).Model(&Notification{}).Where("user_id = ?", userID).Count(&total)

	offset := (page - 1) * pageSize
	err := r.db.WithContext(ctx).
		Where("user_id = ?", userID).
		Order("id desc").
		Offset(offset).Limit(pageSize).
		Find(&notifications).Error
	return notifications, total, err
}
