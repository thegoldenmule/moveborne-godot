// Package httpapi wires the service's public HTTP surface: the platform
// health probe plus the two connectivity-proof endpoints (ping, snap-check).
package httpapi

import (
	"context"
	"encoding/json"
	"log/slog"
	"net/http"
	"time"

	"metagame/internal/config"
	"metagame/internal/snaps"
)

// userIDHeader is stamped by the Snapser gateway after validating the session
// token (see the accepted auth ADR: trust the gateway, no self-rolled auth).
const userIDHeader = "User-Id"

const snapCheckTimeout = 5 * time.Second

type HealthResponse struct {
	Status string `json:"status"`
}

type PingResponse struct {
	OK      bool   `json:"ok"`
	UserID  string `json:"userId"`
	Version string `json:"version"`
}

type SnapCheckResponse struct {
	Snap       string `json:"snap"`
	RPC        string `json:"rpc"`
	DurationMS int64  `json:"durationMs"`
	Upstream   string `json:"upstream"`
}

type errorResponse struct {
	Error string `json:"error"`
}

type Server struct {
	cfg     config.Config
	version string
	auth    *snaps.AuthClient // nil when SNAPEND_AUTH_GRPC_URL is unset
}

// Handler builds the route table. The gateway forwards the full prefix
// without stripping it, so app routes live under cfg.BasePath; /health is
// also answered unprefixed for the platform readiness probe.
func Handler(cfg config.Config, version string, auth *snaps.AuthClient) http.Handler {
	s := &Server{cfg: cfg, version: version, auth: auth}
	mux := http.NewServeMux()
	mux.HandleFunc("GET /health", s.handleHealth)
	if cfg.BasePath != "" {
		mux.HandleFunc("GET "+cfg.BasePath+"/health", s.handleHealth)
	}
	mux.HandleFunc("GET "+cfg.BasePath+"/ping", s.requireUser(s.handlePing))
	mux.HandleFunc("GET "+cfg.BasePath+"/snap-check", s.requireUser(s.handleSnapCheck))
	return mux
}

// requireUser gates a handler on the gateway-stamped User-Id header, so no
// endpoint can forget the session check (only /health is unauthenticated).
func (s *Server) requireUser(next func(w http.ResponseWriter, r *http.Request, userID string)) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		userID := r.Header.Get(userIDHeader)
		if userID == "" {
			writeJSON(w, http.StatusUnauthorized, errorResponse{Error: "missing User-Id header"})
			return
		}
		next(w, r, userID)
	}
}

func (s *Server) handleHealth(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, HealthResponse{Status: "ok"})
}

func (s *Server) handlePing(w http.ResponseWriter, r *http.Request, userID string) {
	writeJSON(w, http.StatusOK, PingResponse{OK: true, UserID: userID, Version: s.version})
}

func (s *Server) handleSnapCheck(w http.ResponseWriter, r *http.Request, userID string) {
	resp := SnapCheckResponse{Snap: "auth", RPC: snaps.GetUserRPC}
	if s.auth == nil {
		resp.Upstream = "unconfigured: SNAPEND_AUTH_GRPC_URL is not set"
		writeJSON(w, http.StatusBadGateway, resp)
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), snapCheckTimeout)
	defer cancel()
	elapsed, err := s.auth.CheckGetUser(ctx, userID)
	resp.DurationMS = elapsed.Milliseconds()
	if err != nil {
		resp.Upstream = err.Error()
		slog.Warn("snap-check failed", "snap", resp.Snap, "rpc", resp.RPC, "err", err)
		writeJSON(w, http.StatusBadGateway, resp)
		return
	}
	resp.Upstream = "OK"
	writeJSON(w, http.StatusOK, resp)
}

func writeJSON(w http.ResponseWriter, code int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	if err := json.NewEncoder(w).Encode(v); err != nil {
		slog.Error("write response", "err", err)
	}
}
