package user

import "time"

type User struct {
	ID        uint      `json:"id" gorm:"primaryKey"`
	Username  string    `json:"username" gorm:"size:50;uniqueIndex;not null"`
	Email     string    `json:"email" gorm:"size:100;uniqueIndex;not null"`
	Phone     string    `json:"phone" gorm:"size:20"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

type CreateUserReq struct {
	Username string `json:"username" binding:"required"`
	Email    string `json:"email" binding:"required,email"`
	Phone    string `json:"phone"`
}

type UpdateUserReq struct {
	Email string `json:"email" binding:"omitempty,email"`
	Phone string `json:"phone"`
}
