package gateway

import (
	"fmt"

	"github.com/gin-gonic/gin"
)

type ServiceConfig struct {
	UserSvcURL         string
	OrderSvcURL        string
	InventorySvcURL    string
	PaymentSvcURL      string
	NotificationSvcURL string
}

func SetupRouter(handler *Handler) *gin.Engine {
	gin.SetMode(gin.ReleaseMode)
	r := gin.New()
	r.Use(gin.Recovery())

	// Health check
	r.GET("/health", handler.Health)

	// API routes - proxy to backend services
	api := r.Group("/api")
	{
		// User service: /api/users/*
		api.Any("/users/*action", handler.ProxyUser)

		// Order service: /api/orders/* and /api/users/:user_id/orders
		api.Any("/orders/*action", handler.ProxyOrder)
		api.Any("/users/:user_id/orders", handler.ProxyOrder)

		// Inventory service: /api/products/*
		api.Any("/products/*action", handler.ProxyInventory)

		// Payment service: /api/payments/*
		api.Any("/payments/*action", handler.ProxyPayment)

		// Notification service: /api/notifications/* and /api/users/:user_id/notifications
		api.Any("/notifications/*action", handler.ProxyNotification)
		api.Any("/users/:user_id/notifications", handler.ProxyNotification)
	}

	return r
}

// DefaultServiceConfig creates a config with default service URLs.
func DefaultServiceConfig() *ServiceConfig {
	return &ServiceConfig{
		UserSvcURL:         "http://localhost:8081",
		OrderSvcURL:        "http://localhost:8082",
		InventorySvcURL:    "http://localhost:8083",
		PaymentSvcURL:      "http://localhost:8084",
		NotificationSvcURL: "http://localhost:8085",
	}
}

// PrintRoutes prints all registered routes.
func PrintRoutes(r *gin.Engine) {
	routes := r.Routes()
	fmt.Println("[gateway] registered routes:")
	for _, route := range routes {
		fmt.Printf("  %s %s\n", route.Method, route.Path)
	}
}
