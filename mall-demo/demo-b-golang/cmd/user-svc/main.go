package main

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"mall-demo/internal/pkg/config"
	"mall-demo/internal/pkg/database"
	redispkg "mall-demo/internal/pkg/redis"
	"mall-demo/internal/pkg/telemetry"
	"mall-demo/internal/user"

	"github.com/gin-gonic/gin"
)

func main() {
	cfg := config.Load("user-svc")

	// Init OTel
	shutdown, err := telemetry.InitTracer(cfg.ServiceName, cfg.OTelEndpoint)
	if err != nil {
		log.Printf("[otel] init failed (non-fatal): %v", err)
	} else {
		defer func() {
			ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			defer cancel()
			shutdown(ctx)
		}()
	}

	// Init DB
	db := database.NewDB(cfg.DSN())

	// Init Redis
	rdb := redispkg.NewRedis(cfg.RedisAddr(), cfg.RedisPassword)

	// Init user service
	repo := user.NewRepository(db)
	repo.AutoMigrate()
	svc := user.NewService(repo, rdb)
	handler := user.NewHandler(svc)

	// Init Gin
	gin.SetMode(gin.ReleaseMode)
	r := gin.New()
	r.Use(gin.Recovery())
	handler.RegisterRoutes(r)

	// Health check
	r.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "ok", "service": "user-svc"})
	})

	addr := ":" + cfg.HTTPPort
	srv := &http.Server{Addr: addr, Handler: r}

	go func() {
		fmt.Printf("[user-svc] HTTP listening on %s\n", addr)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("listen: %v", err)
		}
	}()

	// Graceful shutdown
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	fmt.Println("[user-svc] shutting down...")
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	srv.Shutdown(ctx)
}
