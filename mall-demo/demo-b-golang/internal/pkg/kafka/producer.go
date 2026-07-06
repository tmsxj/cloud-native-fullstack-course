package kafka

import (
	"context"
	"encoding/json"
	"fmt"
	"log"

	"github.com/segmentio/kafka-go"
)

type Producer struct {
	w *kafka.Writer
}

func NewProducer(brokers []string) *Producer {
	w := &kafka.Writer{
		Addr:         kafka.TCP(brokers...),
		Balancer:     &kafka.LeastBytes(),
		BatchSize:    1,
		RequiredAcks: kafka.RequireOne,
	}
	return &Producer{w: w}
}

func (p *Producer) Publish(ctx context.Context, topic string, key string, value interface{}) error {
	data, err := json.Marshal(value)
	if err != nil {
		return fmt.Errorf("marshal kafka message: %w", err)
	}

	err = p.w.WriteMessages(ctx, kafka.Message{
		Topic: topic,
		Key:   []byte(key),
		Value: data,
	})
	if err != nil {
		return fmt.Errorf("publish to %s: %w", topic, err)
	}

	log.Printf("[kafka] published to topic=%s key=%s", topic, key)
	return nil
}

func (p *Producer) Close() error {
	return p.w.Close()
}
