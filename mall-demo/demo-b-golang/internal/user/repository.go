package user

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
	r.db.AutoMigrate(&User{})
}

func (r *Repository) Create(ctx context.Context, u *User) error {
	return r.db.WithContext(ctx).Create(u).Error
}

func (r *Repository) GetByID(ctx context.Context, id uint) (*User, error) {
	var u User
	if err := r.db.WithContext(ctx).First(&u, id).Error; err != nil {
		return nil, fmt.Errorf("user not found: %w", err)
	}
	return &u, nil
}

func (r *Repository) GetByUsername(ctx context.Context, username string) (*User, error) {
	var u User
	if err := r.db.WithContext(ctx).Where("username = ?", username).First(&u).Error; err != nil {
		return nil, fmt.Errorf("user not found: %w", err)
	}
	return &u, nil
}

func (r *Repository) Update(ctx context.Context, id uint, email, phone string) (*User, error) {
	var u User
	if err := r.db.WithContext(ctx).First(&u, id).Error; err != nil {
		return nil, fmt.Errorf("user not found: %w", err)
	}
	updates := map[string]interface{}{}
	if email != "" {
		updates["email"] = email
	}
	if phone != "" {
		updates["phone"] = phone
	}
	if len(updates) > 0 {
		if err := r.db.WithContext(ctx).Model(&u).Updates(updates).Error; err != nil {
			return nil, err
		}
	}
	return &u, nil
}

func (r *Repository) Delete(ctx context.Context, id uint) error {
	return r.db.WithContext(ctx).Delete(&User{}, id).Error
}

func (r *Repository) List(ctx context.Context, page, pageSize int) ([]User, int64, error) {
	var users []User
	var total int64

	r.db.WithContext(ctx).Model(&User{}).Count(&total)

	offset := (page - 1) * pageSize
	err := r.db.WithContext(ctx).Order("id desc").Offset(offset).Limit(pageSize).Find(&users).Error
	return users, total, err
}
