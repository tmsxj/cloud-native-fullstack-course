package payment

import (
	"log"
	"net"
	"net/http"
	"strconv"

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
	r.GET("/payments", h.List)
	r.GET("/payments/:order_id", h.GetByOrderID)
}

func (h *Handler) GetByOrderID(c *gin.Context) {
	orderID, err := strconv.ParseUint(c.Param("order_id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid order_id"})
		return
	}

	p, err := h.svc.GetByOrderID(c.Request.Context(), uint(orderID))
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "payment not found"})
		return
	}

	c.JSON(http.StatusOK, p)
}

func (h *Handler) List(c *gin.Context) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))

	payments, total, err := h.svc.List(c.Request.Context(), page, pageSize)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"items": payments,
		"total": total,
		"page":  page,
	})
}

// StartGRPCServer starts the gRPC server for payment service.
func StartGRPCServer(svc *Service, port string) {
	grpcSrv := grpc.NewServer()
	RegisterService(grpcSrv, svc)

	lis, err := net.Listen("tcp", ":"+port)
	if err != nil {
		log.Fatalf("[payment-svc] gRPC listen: %v", err)
	}

	log.Printf("[payment-svc] gRPC listening on :%s", port)
	if err := grpcSrv.Serve(lis); err != nil {
		log.Fatalf("[payment-svc] gRPC serve: %v", err)
	}
}
