// Package repository provides internal APIs for accessing shared domain data.
// Other services in the monorepo can import this package directly.
package repository

import (
	"context"
	"fmt"
	"sync"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/csaptu/flow/pkg/config"
)

var (
	pool     *pgxpool.Pool
	poolOnce sync.Once
	poolErr  error
)

// Init initializes the shared database connection pool.
// This should be called once at startup by any service that needs shared data.
// Safe to call multiple times - only initializes once.
func Init(cfg *config.Config) error {
	poolOnce.Do(func() {
		poolConfig, err := pgxpool.ParseConfig(cfg.Databases.Shared.DSN())
		if err != nil {
			poolErr = fmt.Errorf("failed to parse shared db config: %w", err)
			return
		}

		// Set pool limits
		maxConns := cfg.Databases.Shared.MaxOpenConns
		if maxConns <= 0 {
			maxConns = 10 // Lower default for cross-service access
		}
		minConns := cfg.Databases.Shared.MaxIdleConns
		if minConns <= 0 {
			minConns = 2
		}
		poolConfig.MaxConns = int32(maxConns)
		poolConfig.MinConns = int32(minConns)
		poolConfig.MaxConnLifetime = cfg.Databases.Shared.MaxLifetime

		pool, poolErr = pgxpool.NewWithConfig(context.Background(), poolConfig)
		if poolErr != nil {
			poolErr = fmt.Errorf("failed to connect to shared db: %w", poolErr)
			return
		}

		// Test connection
		if err := pool.Ping(context.Background()); err != nil {
			poolErr = fmt.Errorf("failed to ping shared db: %w", err)
			return
		}
	})

	return poolErr
}

// Close closes the shared database connection pool.
// Should be called during graceful shutdown.
func Close() {
	if pool != nil {
		pool.Close()
	}
}

// getPool returns the shared database pool, panics if not initialized.
func getPool() *pgxpool.Pool {
	if pool == nil {
		panic("shared repository not initialized - call repository.Init() first")
	}
	return pool
}
