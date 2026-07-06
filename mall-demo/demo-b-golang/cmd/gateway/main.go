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

	"mall-demo/internal/gateway"
	"mall-demo/internal/pkg/config"
	"mall-demo/internal/pkg/telemetry"
)

func main() {
	cfg := config.Load("gateway")

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

	// Build service URLs from config
	svcCfg := &gateway.ServiceConfig{
		UserSvcURL:         fmt.Sprintf("http://%s", cfg.UserSvcAddr),
		OrderSvcURL:        fmt.Sprintf("http://%s", cfg.OrderSvcAddr),
		InventorySvcURL:    fmt.Sprintf("http://%s", cfg.InventorySvcAddr),
		PaymentSvcURL:      fmt.Sprintf("http://%s", cfg.PaymentSvcAddr),
		NotificationSvcURL: fmt.Sprintf("http://%s", "localhost:8085"),
	}

	handler, err := gateway.NewHandler(svcCfg)
	if err != nil {
		log.Fatalf("[gateway] create handler: %v", err)
	}

	r := gateway.SetupRouter(handler)
	gateway.PrintRoutes(r)

	addr := ":" + cfg.HTTPPort
	srv := &http.Server{Addr: addr, Handler: r}

	go func() {
		fmt.Printf("[gateway] HTTP listening on %s\n", addr)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("listen: %v", err)
		}
	}()

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	fmt.Println("[gateway] shutting down...")
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	srv.Shutdown(ctx)
}
