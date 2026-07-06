package kafka

import (
	"context"
	"encoding/json"
	"fmt"
	"log"

	"github.com/segmentio/kafka-go"
)

type MessageHandler func(ctx context.Context, key string, value []byte) error

type Consumer struct {
	r *kafka.Reader
}

func NewConsumer(brokers []string, topic, groupID string) *Consumer {
	r := kafka.NewReader(kafka.ReaderConfig{
		Brokers:  brokers,
		GroupID:  groupID,
		Topic:    topic,
		MinBytes: 1,
		MaxBytes: 1e6,
	})
	return &Consumer{r: r}
}

func (c *Consumer) Consume(ctx context.Context, handler MessageHandler) error {
	log.Printf("[kafka] consumer started, waiting for messages...")
	for {
		m, err := c.r.ReadMessage(ctx)
		if err != nil {
			return fmt.Errorf("read message: %w", err)
		}

		log.Printf("[kafka] received topic=%s partition=%d offset=%d key=%s",
			m.Topic, m.Partition, m.Offset, string(m.Key))

		if err := handler(ctx, string(m.Key), m.Value); err != nil {
			log.Printf("[kafka] handler error: %v", err)
		}
	}
}

func (c *Consumer) Close() error {
	return c.r.Close()
}

// DecodeJSON decodes a Kafka message value into the target struct.
func DecodeJSON(data []byte, target interface{}) error {
	return json.Unmarshal(data, target)
}
