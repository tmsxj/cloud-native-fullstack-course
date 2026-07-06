package user

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/redis/go-redis/v9"
)

type Service struct {
	repo *Repository
	rdb  *redis.Client
}

func NewService(repo *Repository, rdb *redis.Client) *Service {
	return &Service{repo: repo, rdb: rdb}
}

func (s *Service) Create(ctx context.Context, req *CreateUserReq) (*User, error) {
	u := &User{
		Username: req.Username,
		Email:    req.Email,
		Phone:    req.Phone,
	}
	if err := s.repo.Create(ctx, u); err != nil {
		return nil, fmt.Errorf("create user: %w", err)
	}
	return u, nil
}

func (s *Service) GetByID(ctx context.Context, id uint) (*User, error) {
	// Try Redis cache first
	cacheKey := fmt.Sprintf("user:%d", id)
	cached, err := s.rdb.Get(ctx, cacheKey).Result()
	if err == nil {
		var u User
		if json.Unmarshal([]byte(cached), &u) == nil {
			return &u, nil
		}
	}

	u, err := s.repo.GetByID(ctx, id)
	if err != nil {
		return nil, err
	}

	// Cache for 5 minutes
	if data, err := json.Marshal(u); err == nil {
		s.rdb.Set(ctx, cacheKey, string(data), 5*time.Minute)
	}

	return u, nil
}

func (s *Service) GetByUsername(ctx context.Context, username string) (*User, error) {
	return s.repo.GetByUsername(ctx, username)
}

func (s *Service) Update(ctx context.Context, id uint, req *UpdateUserReq) (*User, error) {
	u, err := s.repo.Update(ctx, id, req.Email, req.Phone)
	if err != nil {
		return nil, err
	}

	// Invalidate cache
	cacheKey := fmt.Sprintf("user:%d", id)
	s.rdb.Del(ctx, cacheKey)

	return u, nil
}

func (s *Service) Delete(ctx context.Context, id uint) error {
	if err := s.repo.Delete(ctx, id); err != nil {
		return err
	}
	cacheKey := fmt.Sprintf("user:%d", id)
	s.rdb.Del(ctx, cacheKey)
	return nil
}

func (s *Service) List(ctx context.Context, page, pageSize int) ([]User, int64, error) {
	if page < 1 {
		page = 1
	}
	if pageSize < 1 || pageSize > 100 {
		pageSize = 20
	}
	return s.repo.List(ctx, page, pageSize)
}
