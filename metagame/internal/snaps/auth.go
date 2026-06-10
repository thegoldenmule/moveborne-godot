// Package snaps holds gRPC clients for other snaps in the snapend, built on
// the vendored Snapser-generated stubs in snapser-pb (each imported under a
// distinct alias because every generated package is named `proto`).
package snaps

import (
	"context"
	"fmt"
	"time"

	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
	"google.golang.org/grpc/metadata"
	"google.golang.org/grpc/status"

	authpb "snapser-pb/auth"
)

// AuthClient wraps the Auth snap's gRPC surface for the snap-check proof
// endpoint. Connections are plaintext: internal snap addresses are only
// reachable inside the snapend network.
type AuthClient struct {
	conn           *grpc.ClientConn
	client         authpb.AuthServiceClient
	internalHeader string
}

// NewAuthClient prepares a lazily-connecting client for the Auth snap.
// internalHeader is the SNAPEND_INTERNAL_HEADER value; when non-empty it is
// attached to every call as `gateway` metadata, mirroring how the documented
// internal HTTP example passes it as the gateway header.
func NewAuthClient(addr, internalHeader string) (*AuthClient, error) {
	conn, err := grpc.NewClient(addr, grpc.WithTransportCredentials(insecure.NewCredentials()))
	if err != nil {
		return nil, fmt.Errorf("dial auth snap %q: %w", addr, err)
	}
	return &AuthClient{
		conn:           conn,
		client:         authpb.NewAuthServiceClient(conn),
		internalHeader: internalHeader,
	}, nil
}

// GetUserRPC is the fully-qualified method snap-check invokes.
const GetUserRPC = authpb.AuthService_GetUser_FullMethodName

// CheckGetUser performs one read-only GetUser round trip for the given user
// id and reports the duration. On failure the returned error's message is the
// upstream gRPC status (code + message).
func (c *AuthClient) CheckGetUser(ctx context.Context, userID string) (time.Duration, error) {
	if c.internalHeader != "" {
		ctx = metadata.AppendToOutgoingContext(ctx, "gateway", c.internalHeader)
	}
	start := time.Now()
	_, err := c.client.GetUser(ctx, &authpb.GetUserRequest{UserId: userID})
	elapsed := time.Since(start)
	if err != nil {
		st := status.Convert(err)
		return elapsed, fmt.Errorf("%s: %s", st.Code(), st.Message())
	}
	return elapsed, nil
}

func (c *AuthClient) Close() error {
	return c.conn.Close()
}
