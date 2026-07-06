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

	"mall-demo/internal/inventory"
	"mall-demo/internal/order"
	"mall-demo/internal/payment"
	"mall-demo/internal/pkg/config"
	"mall-demo/internal/pkg/database"
	kafkapkg "mall-demo/internal/pkg/kafka"
	"mall-demo/internal/pkg/telemetry"

	"github.com/gin-gonic/gin"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
)

func main() {
	cfg := config.Load("order-svc")

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

	// Init Kafka producer
	producer := kafkapkg.NewProducer(cfg.KafkaBrokers)
	defer producer.Close()

	// gRPC connections to inventory-svc and payment-svc
	invConn, err := grpc.Dial(cfg.InventorySvcAddr,
		grpc.WithTransportCredentials(insecure.NewCredentials()),
		grpc.WithBlock(),
		grpc.WithTimeout(5*time.Second),
	)
	if err != nil {
		log.Fatalf("[order-svc] connect to inventory-svc: %v", err)
	}
	defer invConn.Close()

	payConn, err := grpc.Dial(cfg.PaymentSvcAddr,
		grpc.WithTransportCredentials(insecure.NewCredentials()),
		grpc.WithBlock(),
		grpc.WithTimeout(5*time.Second),
	)
	if err != nil {
		log.Fatalf("[order-svc] connect to payment-svc: %v", err)
	}
	defer payConn.Close()

	// Create gRPC clients
	invClient := inventory.NewInventoryServiceClient(invConn)
	payClient := payment.NewPaymentServiceClient(payConn)

	// Create adapters that implement the Service interfaces
	invAdapter := &inventoryClientAdapter{client: invClient}
	payAdapter := &paymentClientAdapter{client: payClient}

	// Init order service
	repo := order.NewRepository(db)
	repo.AutoMigrate()
	svc := order.NewService(repo, producer, invAdapter, payAdapter)
	handler := order.NewHandler(svc)

	// Init Gin
	gin.SetMode(gin.ReleaseMode)
	r := gin.New()
	r.Use(gin.Recovery())
	handler.RegisterRoutes(r)

	r.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "ok", "service": "order-svc"})
	})

	addr := ":" + cfg.HTTPPort
	srv := &http.Server{Addr: addr, Handler: r}

	go func() {
		fmt.Printf("[order-svc] HTTP listening on %s\n", addr)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("listen: %v", err)
		}
	}()

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	fmt.Println("[order-svc] shutting down...")
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	srv.Shutdown(ctx)
}

// Adapter: implements order.InventoryClient using gRPC
type inventoryClientAdapter struct {
	client inventory.InventoryServiceClient
}

func (a *inventoryClientAdapter) DeductStock(ctx context.Context, productID uint, quantity int) error {
	_, err := a.client.DeductStock(ctx, &inventory.DeductStockRequest{
		ProductId: uint64(productID),
		Quantity:  int64(quantity),
	})
	return err
}

// Adapter: implements order.PaymentClient using gRPC
type paymentClientAdapter struct {
	client payment.PaymentServiceClient
}

func (a *paymentClientAdapter) ProcessPayment(ctx context.Context, orderID uint, amount float64) error {
	resp, err := a.client.ProcessPayment(ctx, &payment.PaymentRequest{
		OrderId: uint64(orderID),
		Amount:  amount,
	})
	if err != nil {
		return err
	}
	if !resp.Success {
		return fmt.Errorf("payment declined: %s", resp.Message)
	}
	return nil
}
