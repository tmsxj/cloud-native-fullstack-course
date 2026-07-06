package inventory

import (
	"encoding/json"

	"google.golang.org/grpc/encoding"
)

func init() {
	// Register a custom JSON codec for gRPC so we can use plain Go structs
	// without protobuf. The name "proto" overrides the default proto codec.
	encoding.RegisterCodec(jsonCodec{})
}

// jsonCodec implements gRPC encoding.Codec using JSON.
type jsonCodec struct{}

func (jsonCodec) Marshal(v any) ([]byte, error) {
	return json.Marshal(v)
}

func (jsonCodec) Unmarshal(data []byte, v any) error {
	return json.Unmarshal(data, v)
}

func (jsonCodec) Name() string {
	return "proto"
}
