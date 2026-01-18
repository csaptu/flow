package repository

import (
	"context"
	"time"

	"github.com/jackc/pgx/v5"
)

// AIPromptConfig represents a configurable AI prompt instruction
type AIPromptConfig struct {
	Key         string
	Value       string
	Description *string
	UpdatedAt   time.Time
	UpdatedBy   *string
}

// GetAIPromptConfig retrieves a single AI prompt configuration by key
func GetAIPromptConfig(ctx context.Context, key string) (string, error) {
	db := getPool()

	var value string
	err := db.QueryRow(ctx, `
		SELECT value FROM ai_prompt_configs WHERE key = $1
	`, key).Scan(&value)

	if err == pgx.ErrNoRows {
		return "", nil
	}
	if err != nil {
		return "", err
	}

	return value, nil
}

// GetAllAIPromptConfigs retrieves all AI prompt configurations
func GetAllAIPromptConfigs(ctx context.Context) (map[string]AIPromptConfig, error) {
	db := getPool()

	rows, err := db.Query(ctx, `
		SELECT key, value, description, updated_at, updated_by
		FROM ai_prompt_configs
		ORDER BY key
	`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	configs := make(map[string]AIPromptConfig)
	for rows.Next() {
		var c AIPromptConfig
		err := rows.Scan(&c.Key, &c.Value, &c.Description, &c.UpdatedAt, &c.UpdatedBy)
		if err != nil {
			continue
		}
		configs[c.Key] = c
	}

	return configs, nil
}

// GetAIPromptConfigsAsMap returns all configs as a simple key-value map
func GetAIPromptConfigsAsMap(ctx context.Context) (map[string]string, error) {
	db := getPool()

	rows, err := db.Query(ctx, `
		SELECT key, value FROM ai_prompt_configs
	`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	configs := make(map[string]string)
	for rows.Next() {
		var key, value string
		err := rows.Scan(&key, &value)
		if err != nil {
			continue
		}
		configs[key] = value
	}

	return configs, nil
}

// UpdateAIPromptConfig updates a single AI prompt configuration
func UpdateAIPromptConfig(ctx context.Context, key, value, updatedBy string) error {
	db := getPool()

	_, err := db.Exec(ctx, `
		UPDATE ai_prompt_configs
		SET value = $2, updated_at = NOW(), updated_by = $3
		WHERE key = $1
	`, key, value, updatedBy)

	return err
}

// ListAIPromptConfigs returns all configs as a slice (for API responses)
func ListAIPromptConfigs(ctx context.Context) ([]AIPromptConfig, error) {
	db := getPool()

	rows, err := db.Query(ctx, `
		SELECT key, value, description, updated_at, updated_by
		FROM ai_prompt_configs
		ORDER BY key
	`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var configs []AIPromptConfig
	for rows.Next() {
		var c AIPromptConfig
		err := rows.Scan(&c.Key, &c.Value, &c.Description, &c.UpdatedAt, &c.UpdatedBy)
		if err != nil {
			continue
		}
		configs = append(configs, c)
	}

	return configs, nil
}
