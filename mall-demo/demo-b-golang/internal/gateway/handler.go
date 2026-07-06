package gateway

import (
	"net/http"
	"net/http/httputil"
	"net/url"
	"strings"

	"github.com/gin-gonic/gin"
)

type Handler struct {
	userSvcURL         *url.URL
	orderSvcURL        *url.URL
	inventorySvcURL    *url.URL
	paymentSvcURL      *url.URL
	notificationSvcURL *url.URL
}

func NewHandler(cfg *ServiceConfig) (*Handler, error) {
	userURL, err := url.Parse(cfg.UserSvcURL)
	if err != nil {
		return nil, err
	}
	orderURL, err := url.Parse(cfg.OrderSvcURL)
	if err != nil {
		return nil, err
	}
	inventoryURL, err := url.Parse(cfg.InventorySvcURL)
	if err != nil {
		return nil, err
	}
	paymentURL, err := url.Parse(cfg.PaymentSvcURL)
	if err != nil {
		return nil, err
	}
	notificationURL, err := url.Parse(cfg.NotificationSvcURL)
	if err != nil {
		return nil, err
	}

	return &Handler{
		userSvcURL:         userURL,
		orderSvcURL:        orderURL,
		inventorySvcURL:    inventoryURL,
		paymentSvcURL:      paymentURL,
		notificationSvcURL: notificationURL,
	}, nil
}

func (h *Handler) Health(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{
		"status":  "ok",
		"service": "gateway",
	})
}

func (h *Handler) ProxyToService(target *url.URL) gin.HandlerFunc {
	return func(c *gin.Context) {
		proxy := httputil.NewSingleHostReverseProxy(target)
		proxy.ErrorHandler = func(w http.ResponseWriter, r *http.Request, err error) {
			c.JSON(http.StatusBadGateway, gin.H{
				"error":  "service unavailable",
				"detail": err.Error(),
			})
		}
		// Modify the request
		c.Request.URL.Path = strings.TrimPrefix(c.Request.URL.Path, "/api")
		c.Request.Host = target.Host

		proxy.ServeHTTP(c.Writer, c.Request)
	}
}

func (h *Handler) ProxyUser(c *gin.Context) {
	h.ProxyToService(h.userSvcURL)(c)
}

func (h *Handler) ProxyOrder(c *gin.Context) {
	h.ProxyToService(h.orderSvcURL)(c)
}

func (h *Handler) ProxyInventory(c *gin.Context) {
	h.ProxyToService(h.inventorySvcURL)(c)
}

func (h *Handler) ProxyPayment(c *gin.Context) {
	h.ProxyToService(h.paymentSvcURL)(c)
}

func (h *Handler) ProxyNotification(c *gin.Context) {
	h.ProxyToService(h.notificationSvcURL)(c)
}
