package main

import (
	"context"
	"fmt"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/rs/zerolog"
	"github.com/rs/zerolog/log"
	"github.com/csaptu/flow/pkg/config"
	"github.com/csaptu/flow/shared"
)

func main() {
	// Setup logging
	zerolog.TimeFieldFormat = time.RFC3339
	if os.Getenv("ENVIRONMENT") != "production" {
		log.Logger = log.Output(zerolog.ConsoleWriter{Out: os.Stderr})
	}

	// Load configuration
	cfg, err := config.LoadForService("shared")
	if err != nil {
		log.Fatal().Err(err).Msg("Failed to load configuration")
	}

	if cfg.Auth.JWTSecret == "" {
		log.Fatal().Msg("JWT_SECRET is empty! Check .env file loading")
	}

	log.Info().
		Str("environment", cfg.Server.Environment).
		Int("port", cfg.Server.Port).
		Int("jwt_secret_len", len(cfg.Auth.JWTSecret)).
		Str("jwt_secret_preview", cfg.Auth.JWTSecret[:8]+"...").
		Msg("Starting shared-service")

	// Create and start server
	server, err := shared.NewServer(cfg)
	if err != nil {
		log.Fatal().Err(err).Msg("Failed to create server")
	}

	// Start server in goroutine
	go func() {
		addr := fmt.Sprintf("%s:%d", cfg.Server.Host, cfg.Server.Port)
		if err := server.Listen(addr); err != nil {
			log.Fatal().Err(err).Msg("Server failed to start")
		}
	}()

	log.Info().Msg("Server started successfully")

	// Wait for interrupt signal
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	log.Info().Msg("Shutting down server...")

	// Graceful shutdown
	ctx, cancel := context.WithTimeout(context.Background(), cfg.Server.ShutdownTimeout)
	defer cancel()

	if err := server.ShutdownWithContext(ctx); err != nil {
		log.Error().Err(err).Msg("Server shutdown error")
	}

	log.Info().Msg("Server stopped")
}
