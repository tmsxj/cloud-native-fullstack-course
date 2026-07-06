package inventory

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net"
	"net/http"
	"strconv"

	kafkapkg "mall-demo/internal/pkg/kafka"

	"github.com/gin-gonic/gin"
	"google.golang.org/grpc"
)

type Handler struct {
	svc *Service
}

func NewHandler(svc *Service) *Handler {
	return &Handler{svc: svc}
}

func (h *Handler) RegisterRoutes(r *gin.Engine) {
	r.GET("/products", h.List)
	r.GET("/products/:id", h.GetByID)
	r.POST("/products", h.Create)
	r.PUT("/products/:id/stock", h.UpdateStock)
}

func (h *Handler) Create(c *gin.Context) {
	var req CreateProductReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	p, err := h.svc.CreateProduct(c.Request.Context(), &req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, p)
}

func (h *Handler) GetByID(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
		return
	}

	p, err := h.svc.GetByID(c.Request.Context(), uint(id))
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "product not found"})
		return
	}

	c.JSON(http.StatusOK, p)
}

func (h *Handler) UpdateStock(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
		return
	}

	var req UpdateStockReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if err := h.svc.UpdateStock(c.Request.Context(), uint(id), req.Stock); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "stock updated"})
}

func (h *Handler) List(c *gin.Context) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))

	products, total, err := h.svc.List(c.Request.Context(), page, pageSize)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"items": products,
		"total": total,
		"page":  page,
	})
}

// StartGRPCServer starts the gRPC server for inventory service.
func StartGRPCServer(svc *Service, port string) {
	grpcSrv := grpc.NewServer()
	RegisterService(grpcSrv, svc)

	lis, err := net.Listen("tcp", ":"+port)
	if err != nil {
		log.Fatalf("[inventory-svc] gRPC listen: %v", err)
	}

	fmt.Printf("[inventory-svc] gRPC listening on :%s\n", port)
	if err := grpcSrv.Serve(lis); err != nil {
		log.Fatalf("[inventory-svc] gRPC serve: %v", err)
	}
}

// StartKafkaConsumer starts the Kafka consumer for inventory events.
func StartKafkaConsumer(svc *Service, brokers []string) {
	consumer := kafkapkg.NewConsumer(brokers, "order-events", "inventory-svc-group")

	handler := func(ctx context.Context, key string, value []byte) error {
		log.Printf("[inventory-svc] received event: key=%s", key)

		var event struct {
			OrderID   uint    `json:"order_id"`
			ProductID uint    `json:"product_id"`
			Quantity  int     `json:"quantity"`
			Action    string  `json:"action"`
			Status    string  `json:"status"`
		}
		if err := json.Unmarshal(value, &event); err != nil {
			return fmt.Errorf("unmarshal: %w", err)
		}

		// If order failed, restore stock
		if event.Action == "failed" && event.ProductID > 0 && event.Quantity > 0 {
			log.Printf("[inventory-svc] restoring stock: product=%d qty=%d", event.ProductID, event.Quantity)
			p, err := svc.GetByID(ctx, event.ProductID)
			if err == nil {
				_ = svc.UpdateStock(ctx, event.ProductID, p.Stock+event.Quantity)
				log.Printf("[inventory-svc] stock restored: product=%d new_stock=%d", event.ProductID, p.Stock+event.Quantity)
			}
		}

		return nil
	}

	log.Println("[inventory-svc] starting kafka consumer...")
	if err := consumer.Consume(context.Background(), handler); err != nil {
		log.Printf("[inventory-svc] kafka consumer error: %v", err)
	}
}
