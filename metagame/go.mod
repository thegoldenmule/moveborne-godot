module metagame

go 1.26

require (
	google.golang.org/grpc v1.81.1
	snapser-pb v0.0.0
)

require (
	github.com/envoyproxy/protoc-gen-validate v1.3.3 // indirect
	github.com/grpc-ecosystem/grpc-gateway/v2 v2.29.0 // indirect
	golang.org/x/net v0.51.0 // indirect
	golang.org/x/sys v0.42.0 // indirect
	golang.org/x/text v0.36.0 // indirect
	google.golang.org/genproto/googleapis/api v0.0.0-20260608224507-4308a22a1bab // indirect
	google.golang.org/genproto/googleapis/rpc v0.0.0-20260526163538-3dc84a4a5aaa // indirect
	google.golang.org/protobuf v1.36.11 // indirect
)

replace snapser-pb => ../snapser-pb
