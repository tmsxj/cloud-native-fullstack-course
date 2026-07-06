package config

import "os"

type Config struct {
	ServiceName string
	HTTPPort    string
	GRPCPort    string

	MySQLHost     string
	MySQLPort     string
	MySQLUser     string
	MySQLPassword string
	MySQLDB       string

	RedisHost     string
	RedisPort     string
	RedisPassword string

	KafkaBrokers []string

	OTelEndpoint string

	// gRPC service addresses
	UserSvcAddr      string
	OrderSvcAddr     string
	InventorySvcAddr string
	PaymentSvcAddr   string
}

func Load(serviceName string) *Config {
	return &Config{
		ServiceName: serviceName,
		HTTPPort:     getEnv("HTTP_PORT", "8080"),
		GRPCPort:     getEnv("GRPC_PORT", "50051"),

		MySQLHost:     getEnv("MYSQL_HOST", "192.168.1.61"),
		MySQLPort:     getEnv("MYSQL_PORT", "3306"),
		MySQLUser:     getEnv("MYSQL_USER", "root"),
		MySQLPassword: getEnv("MYSQL_PASSWORD", "Harbor12345"),
		MySQLDB:       getEnv("MYSQL_DB", "mall_demo"),

		RedisHost:     getEnv("REDIS_HOST", "192.168.1.61"),
		RedisPort:     getEnv("REDIS_PORT", "6379"),
		RedisPassword: getEnv("REDIS_PASSWORD", "Harbor12345"),

		KafkaBrokers: []string{getEnv("KAFKA_BROKERS", "192.168.1.61:9092")},

		OTelEndpoint: getEnv("OTEL_ENDPOINT", "otel-collector.monitoring:4317"),

		UserSvcAddr:      getEnv("USER_SVC_ADDR", "localhost:50051"),
		OrderSvcAddr:     getEnv("ORDER_SVC_ADDR", "localhost:50052"),
		InventorySvcAddr: getEnv("INVENTORY_SVC_ADDR", "localhost:50053"),
		PaymentSvcAddr:   getEnv("PAYMENT_SVC_ADDR", "localhost:50054"),
	}
}

func (c *Config) DSN() string {
	return c.MySQLUser + ":" + c.MySQLPassword + "@tcp(" + c.MySQLHost + ":" + c.MySQLPort + ")/" + c.MySQLDB + "?charset=utf8mb4&parseTime=True&loc=Local"
}

func (c *Config) RedisAddr() string {
	return c.RedisHost + ":" + c.RedisPort
}

func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
