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

	"mall-demo/internal/payment"
	"mall-demo/internal/pkg/config"
	"mall-demo/internal/pkg/database"
	"mall-demo/internal/pkg/telemetry"

	"github.com/gin-gonic/gin"
)

func main() {
	cfg := config.Load("payment-svc")

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

	// Init service
	repo := payment.NewRepository(db)
	repo.AutoMigrate()
	svc := payment.NewService(repo)

	// Start gRPC server in background
	go payment.StartGRPCServer(svc, cfg.GRPCPort)

	// Init Gin HTTP server
	gin.SetMode(gin.ReleaseMode)
	r := gin.New()
	r.Use(gin.Recovery())
	handler := payment.NewHandler(svc)
	handler.RegisterRoutes(r)

	r.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "ok", "service": "payment-svc"})
	})

	addr := ":" + cfg.HTTPPort
	srv := &http.Server{Addr: addr, Handler: r}

	go func() {
		fmt.Printf("[payment-svc] HTTP listening on %s\n", addr)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("listen: %v", err)
		}
	}()

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	fmt.Println("[payment-svc] shutting down...")
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	srv.Shutdown(ctx)
}
