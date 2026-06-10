// Package config resolves all service configuration from the environment.
// Everything comes from env vars — no config files — because the Snapser
// platform injects the BYOSnap contract (base path, internal header, snap
// URLs) as environment variables.
package config

import (
	"os"
	"strings"
)

type Config struct {
	// Port the HTTP server listens on. PORT, default 8080 (the BYOSnap
	// external port in the snapser profile).
	Port string
	// BasePath is the unstripped gateway prefix, e.g. /v1/byosnap-metagame.
	// BYOSNAP_BASE_PATH. Empty means routes are served unprefixed only.
	BasePath string
	// InternalHeader is the value snaps expect on the gateway header for
	// internal (snap-to-snap) calls. SNAPEND_INTERNAL_HEADER.
	InternalHeader string
	// AuthSnapAddr is the internal gRPC address of the Auth snap, e.g.
	// service-auth:8080. SNAPEND_AUTH_GRPC_URL (platform-injected).
	AuthSnapAddr string
}

func FromEnv() Config {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	return Config{
		Port:           port,
		BasePath:       strings.TrimSuffix(os.Getenv("BYOSNAP_BASE_PATH"), "/"),
		InternalHeader: os.Getenv("SNAPEND_INTERNAL_HEADER"),
		AuthSnapAddr:   os.Getenv("SNAPEND_AUTH_GRPC_URL"),
	}
}
