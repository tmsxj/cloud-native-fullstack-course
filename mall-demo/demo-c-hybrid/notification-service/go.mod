module github.com/mall-demo/demo-c-hybrid/notification-service

go 1.21

require (
	github.com/IBM/sarama v1.42.1
	github.com/gin-gonic/gin v1.9.1
	go.opentelemetry.io/contrib/instrumentation/github.com/gin-gonic/gin/otelgin v0.46.1
	go.opentelemetry.io/otel v1.21.0
	go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc v1.21.0
	go.opentelemetry.io/otel/sdk v1.21.0
	go.opentelemetry.io/otel/trace v1.21.0
)
