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
	log.Logger = log.Output(zerolog.ConsoleWriter{Out: os.Stderr})

	flag.Parse()
	command := flag.Arg(0)
	if command == "" {
		command = "up"
	}

	cfg, err := config.LoadForService("shared")
	if err != nil {
		log.Fatal().Err(err).Msg("Failed to load configuration")
	}

	migrationsPath := findMigrationsDir()
	log.Info().Str("path", migrationsPath).Msg("Using migrations directory")

	dbURL := os.Getenv("DATABASE_URL")
	if dbURL == "" {
		dbURL = cfg.Databases.Shared.URL
	}
	if dbURL == "" {
		log.Fatal().Msg("No database URL configured. Set DATABASE_URL or SHARED_DB_URL")
	}

	if !strings.Contains(dbURL, "sslmode=") {
		if strings.Contains(dbURL, "?") {
			dbURL += "&sslmode=disable"
		} else {
			dbURL += "?sslmode=disable"
		}
	}

	m, err := migrate.New(
		fmt.Sprintf("file://%s", migrationsPath),
		dbURL,
	)
	if err != nil {
		log.Fatal().Err(err).Msg("Failed to create migrator")
	}
	defer m.Close()

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
		fmt.Println("Commands: up, down, down-all, version, force N")
		os.Exit(1)
	}
}

func findMigrationsDir() string {
	candidates := []string{
		"database/migrations",
		"../database/migrations",
		"../../database/migrations",
		"backend/shared/database/migrations",
	}

	cwd, _ := os.Getwd()

	for _, candidate := range candidates {
		path := filepath.Join(cwd, candidate)
		if info, err := os.Stat(path); err == nil && info.IsDir() {
			absPath, _ := filepath.Abs(path)
			return absPath
		}
	}

	log.Fatal().Msg("Could not find migrations directory")
	return ""
}
