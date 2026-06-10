// byosnap-metagame: the meta-game service scaffold. Proves the two
// connectivity paths — client → gateway → service (ping) and service → snap
// via internal auth (snap-check) — plus the platform health probe. No
// meta-game features live here yet.
package main

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"metagame/internal/config"
	"metagame/internal/httpapi"
	"metagame/internal/snaps"
)

// version is stamped at build time via -ldflags "-X main.version=...".
var version = "dev"

func main() {
	cfg := config.FromEnv()

	var auth *snaps.AuthClient
	if cfg.AuthSnapAddr != "" {
		var err error
		auth, err = snaps.NewAuthClient(cfg.AuthSnapAddr, cfg.InternalHeader)
		if err != nil {
			slog.Error("auth snap client", "err", err)
			os.Exit(1)
		}
		defer auth.Close()
	} else {
		slog.Warn("SNAPEND_AUTH_GRPC_URL not set; snap-check will report unconfigured")
	}

	srv := &http.Server{
		Addr:              ":" + cfg.Port,
		Handler:           httpapi.Handler(cfg, version, auth),
		ReadHeaderTimeout: 10 * time.Second,
		ReadTimeout:       15 * time.Second,
		WriteTimeout:      15 * time.Second, // must outlast the 5s snap-check timeout
		IdleTimeout:       60 * time.Second,
	}

	errCh := make(chan error, 1)
	go func() { errCh <- srv.ListenAndServe() }()
	slog.Info("byosnap-metagame listening",
		"port", cfg.Port, "basePath", cfg.BasePath,
		"authSnap", cfg.AuthSnapAddr, "version", version)

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)
	select {
	case err := <-errCh:
		slog.Error("server", "err", err)
		os.Exit(1)
	case sig := <-stop:
		slog.Info("shutting down", "signal", sig.String())
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		if err := srv.Shutdown(ctx); err != nil && !errors.Is(err, context.DeadlineExceeded) {
			slog.Error("shutdown", "err", err)
		}
	}
}
