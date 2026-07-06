package payment

import (
	"context"

	"google.golang.org/grpc"
)

// gRPC service registration
const (
	paymentServiceName  = "/payment.PaymentService/"
	processPaymentMethod = paymentServiceName + "ProcessPayment"
)

// RegisterService registers the payment service with a gRPC server.
func RegisterService(srv *grpc.Server, svc *Service) {
	desc := grpc.ServiceDesc{
		ServiceName: "payment.PaymentService",
		HandlerType: (*PaymentServiceServer)(nil),
		Methods: []grpc.MethodDesc{
			{
				MethodName: "ProcessPayment",
				Handler:    makeProcessPaymentHandler(svc),
			},
		},
		Streams:  []grpc.StreamDesc{},
		Metadata: nil,
	}
	srv.RegisterService(&desc, svc)
}

func makeProcessPaymentHandler(svc *Service) func(interface{}, context.Context, func(interface{}) error, grpc.UnaryServerInterceptor) (interface{}, error) {
	return func(srv interface{}, ctx context.Context, dec func(interface{}) error, interceptor grpc.UnaryServerInterceptor) (interface{}, error) {
		in := &PaymentRequest{}
		if err := dec(in); err != nil {
			return nil, err
		}
		if interceptor == nil {
			return svc.GRPCProcessPayment(ctx, in)
		}
		info := &grpc.UnaryServerInfo{
			Server:     srv,
			FullMethod: processPaymentMethod,
		}
		handler := func(ctx context.Context, req interface{}) (interface{}, error) {
			return svc.GRPCProcessPayment(ctx, req.(*PaymentRequest))
		}
		return interceptor(ctx, in, info, handler)
	}
}

// --- Client side ---

type paymentClient struct {
	cc *grpc.ClientConn
}

// NewPaymentServiceClient creates a client for the payment gRPC service.
func NewPaymentServiceClient(cc *grpc.ClientConn) PaymentServiceClient {
	return &paymentClient{cc: cc}
}

func (c *paymentClient) ProcessPayment(ctx context.Context, req *PaymentRequest, opts ...interface{}) (*PaymentResponse, error) {
	out := new(PaymentResponse)
	err := c.cc.Invoke(ctx, processPaymentMethod, req, out, filterCallOptions(opts...)...)
	if err != nil {
		return nil, err
	}
	return out, nil
}

func filterCallOptions(opts ...interface{}) []grpc.CallOption {
	var callOpts []grpc.CallOption
	for _, opt := range opts {
		if co, ok := opt.(grpc.CallOption); ok {
			callOpts = append(callOpts, co)
		}
	}
	return callOpts
}

// Ensure interfaces are satisfied
var _ PaymentServiceServer = (*Service)(nil)
var _ PaymentServiceClient = (*paymentClient)(nil)
