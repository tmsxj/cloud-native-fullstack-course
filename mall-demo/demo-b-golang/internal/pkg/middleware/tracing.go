package middleware

import (
	"github.com/gin-gonic/gin"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/trace"
)

func Tracing() gin.HandlerFunc {
	return func(c *gin.Context) {
		tracer := otel.Tracer("gin")
		name := c.Request.Method + " " + c.FullPath()

		ctx, span := tracer.Start(c.Request.Context(), name, trace.WithAttributes(
			attribute.String("http.method", c.Request.Method),
			attribute.String("http.url", c.Request.URL.String()),
			attribute.String("http.host", c.Request.Host),
		))
		defer span.End()

		c.Request = c.Request.WithContext(ctx)
		c.Next()

		span.SetAttributes(
			attribute.Int("http.status_code", c.Writer.Status()),
		)
	}
}
