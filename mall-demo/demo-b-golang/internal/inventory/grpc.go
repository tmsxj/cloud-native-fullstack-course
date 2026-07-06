package inventory

import (
	"context"
	"log"

	"google.golang.org/grpc"
)

// serviceName and method names for gRPC registration
const (
	inventoryServiceName = "/inventory.InventoryService/"
	deductStockMethod    = inventoryServiceName + "DeductStock"
	getStockMethod       = inventoryServiceName + "GetStock"
)

// RegisterService registers the inventory service with a gRPC server.
func RegisterService(srv *grpc.Server, svc *Service) {
	desc := grpc.ServiceDesc{
		ServiceName: "inventory.InventoryService",
		HandlerType: (*InventoryServiceServer)(nil),
		Methods: []grpc.MethodDesc{
			{
				MethodName: "DeductStock",
				Handler:    makeDeductStockHandler(svc),
			},
			{
				MethodName: "GetStock",
				Handler:    makeGetStockHandler(svc),
			},
		},
		Streams:  []grpc.StreamDesc{},
		Metadata: nil,
	}
	srv.RegisterService(&desc, svc)
}

func makeDeductStockHandler(svc *Service) func(interface{}, context.Context, func(interface{}) error, grpc.UnaryServerInterceptor) (interface{}, error) {
	return func(srv interface{}, ctx context.Context, dec func(interface{}) error, interceptor grpc.UnaryServerInterceptor) (interface{}, error) {
		in := &DeductStockRequest{}
		if err := dec(in); err != nil {
			return nil, err
		}
		if interceptor == nil {
			return svc.GRPCDeductStock(ctx, in)
		}
		info := &grpc.UnaryServerInfo{
			Server:     srv,
			FullMethod: deductStockMethod,
		}
		handler := func(ctx context.Context, req interface{}) (interface{}, error) {
			return svc.GRPCDeductStock(ctx, req.(*DeductStockRequest))
		}
		return interceptor(ctx, in, info, handler)
	}
}

func makeGetStockHandler(svc *Service) func(interface{}, context.Context, func(interface{}) error, grpc.UnaryServerInterceptor) (interface{}, error) {
	return func(srv interface{}, ctx context.Context, dec func(interface{}) error, interceptor grpc.UnaryServerInterceptor) (interface{}, error) {
		in := &GetStockRequest{}
		if err := dec(in); err != nil {
			return nil, err
		}
		if interceptor == nil {
			return svc.GRPCGetStock(ctx, in)
		}
		info := &grpc.UnaryServerInfo{
			Server:     srv,
			FullMethod: getStockMethod,
		}
		handler := func(ctx context.Context, req interface{}) (interface{}, error) {
			return svc.GRPCGetStock(ctx, req.(*GetStockRequest))
		}
		return interceptor(ctx, in, info, handler)
	}
}

// --- Client side ---

type inventoryClient struct {
	cc *grpc.ClientConn
}

// NewInventoryServiceClient creates a client for the inventory gRPC service.
func NewInventoryServiceClient(cc *grpc.ClientConn) InventoryServiceClient {
	return &inventoryClient{cc: cc}
}

func (c *inventoryClient) DeductStock(ctx context.Context, req *DeductStockRequest, opts ...interface{}) (*DeductStockResponse, error) {
	out := new(DeductStockResponse)
	err := c.cc.Invoke(ctx, deductStockMethod, req, out, toCallOptions(opts...)...)
	if err != nil {
		return nil, err
	}
	return out, nil
}

func (c *inventoryClient) GetStock(ctx context.Context, req *GetStockRequest, opts ...interface{}) (*GetStockResponse, error) {
	out := new(GetStockResponse)
	err := c.cc.Invoke(ctx, getStockMethod, req, out, toCallOptions(opts...)...)
	if err != nil {
		return nil, err
	}
	return out, nil
}

func toCallOptions(opts ...interface{}) []grpc.CallOption {
	var callOpts []grpc.CallOption
	for _, opt := range opts {
		if co, ok := opt.(grpc.CallOption); ok {
			callOpts = append(callOpts, co)
		}
	}
	return callOpts
}

// Ensure interfaces are satisfied
var _ InventoryServiceServer = (*Service)(nil)
var _ InventoryServiceClient = (*inventoryClient)(nil)

// LogRequest is a helper to log incoming gRPC requests.
func LogRequest(ctx context.Context, method string, req interface{}) {
	log.Printf("[inventory-svc] gRPC %s req=%+v", method, req)
}
