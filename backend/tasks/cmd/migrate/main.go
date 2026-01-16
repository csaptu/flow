package main

import (
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/golang-migrate/migrate/v4"
	_ "github.com/golang-migrate/migrate/v4/database/postgres"
	_ "github.com/golang-migrate/migrate/v4/source/file"
	"github.com/rs/zerolog"
	"github.com/rs/zerolog/log"

	"github.com/csaptu/flow/pkg/config"
)

func main() {
	// Setup logging
	log.Logger = log.Output(zerolog.ConsoleWriter{Out: os.Stderr})

	// Parse command
	flag.Parse()
	command := flag.Arg(0)
	if command == "" {
		command = "up"
	}

	// Load config
	cfg, err := config.LoadForService("tasks")
	if err != nil {
		log.Fatal().Err(err).Msg("Failed to load configuration")
	}

	// Find migrations directory
	migrationsPath := findMigrationsDir()
	log.Info().Str("path", migrationsPath).Msg("Using migrations directory")

	// Get database URL from env or config
	dbURL := os.Getenv("DATABASE_URL")
	if dbURL == "" {
		dbURL = cfg.Databases.Tasks.URL
	}
	if dbURL == "" {
		log.Fatal().Msg("No database URL configured. Set DATABASE_URL or TASKS_DB_URL")
	}

	// Ensure sslmode is set (Railway doesn't require SSL for internal connections)
	if !strings.Contains(dbURL, "sslmode=") {
		if strings.Contains(dbURL, "?") {
			dbURL += "&sslmode=disable"
		} else {
			dbURL += "?sslmode=disable"
		}
	}

	// Create migrator
	m, err := migrate.New(
		fmt.Sprintf("file://%s", migrationsPath),
		dbURL,
	)
	if err != nil {
		log.Fatal().Err(err).Msg("Failed to create migrator")
	}
	defer m.Close()

	// Run command
	switch command {
	case "up":
		log.Info().Msg("Running migrations up...")
		if err := m.Up(); err != nil && err != migrate.ErrNoChange {
			log.Fatal().Err(err).Msg("Migration failed")
		}
		log.Info().Msg("Migrations completed successfully")

	case "down":
		log.Info().Msg("Rolling back last migration...")
		if err := m.Steps(-1); err != nil && err != migrate.ErrNoChange {
			log.Fatal().Err(err).Msg("Rollback failed")
		}
		log.Info().Msg("Rollback completed successfully")

	case "down-all":
		log.Info().Msg("Rolling back ALL migrations...")
		if err := m.Down(); err != nil && err != migrate.ErrNoChange {
			log.Fatal().Err(err).Msg("Rollback failed")
		}
		log.Info().Msg("All migrations rolled back")

	case "version":
		version, dirty, err := m.Version()
		if err != nil && err != migrate.ErrNilVersion {
			log.Fatal().Err(err).Msg("Failed to get version")
		}
		if err == migrate.ErrNilVersion {
			fmt.Println("No migrations applied yet")
		} else {
			fmt.Printf("Version: %d, Dirty: %v\n", version, dirty)
		}

	case "force":
		versionStr := flag.Arg(1)
		if versionStr == "" {
			log.Fatal().Msg("Version required for force command")
		}
		var version int
		fmt.Sscanf(versionStr, "%d", &version)
		if err := m.Force(version); err != nil {
			log.Fatal().Err(err).Msg("Force failed")
		}
		log.Info().Int("version", version).Msg("Forced version")

	default:
		fmt.Println("Usage: migrate [command]")
		fmt.Println("Commands:")
		fmt.Println("  up       - Run all pending migrations")
		fmt.Println("  down     - Rollback last migration")
		fmt.Println("  down-all - Rollback all migrations")
		fmt.Println("  version  - Show current migration version")
		fmt.Println("  force N  - Force set version to N")
		os.Exit(1)
	}
}

// findMigrationsDir locates the migrations directory relative to the executable or working directory
func findMigrationsDir() string {
	// Try relative paths from common locations
	candidates := []string{
		"database/migrations",
		"../database/migrations",
		"../../database/migrations",
		"backend/tasks/database/migrations",
	}

	// Get current working directory
	cwd, _ := os.Getwd()

	for _, candidate := range candidates {
		path := filepath.Join(cwd, candidate)
		if info, err := os.Stat(path); err == nil && info.IsDir() {
			absPath, _ := filepath.Abs(path)
			return absPath
		}
	}

	// Fallback: assume we're in the tasks directory
	log.Fatal().Msg("Could not find migrations directory. Run from backend/tasks or project root.")
	return ""
}
