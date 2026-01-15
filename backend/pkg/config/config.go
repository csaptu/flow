package config

import (
	"fmt"
	"strings"
	"time"

	"github.com/spf13/viper"
)

// Config holds all configuration for the application
type Config struct {
	Server    ServerConfig
	Databases DatabasesConfig
	Redis     RedisConfig
	Auth      AuthConfig
	LLM       LLMConfig
}

// ServerConfig holds server-related configuration
type ServerConfig struct {
	Host            string        `mapstructure:"HOST"`
	Port            int           `mapstructure:"PORT"`
	ShutdownTimeout time.Duration `mapstructure:"SHUTDOWN_TIMEOUT"`
	Environment     string        `mapstructure:"ENVIRONMENT"` // development, staging, production
}

// DatabasesConfig holds database configurations for all domains
type DatabasesConfig struct {
	Shared   DatabaseConfig `mapstructure:"SHARED_DB"`
	Tasks    DatabaseConfig `mapstructure:"TASKS_DB"`
	Projects DatabaseConfig `mapstructure:"PROJECTS_DB"`
}

// DatabaseConfig holds configuration for a single database
type DatabaseConfig struct {
	URL          string `mapstructure:"URL"`
	Host         string `mapstructure:"HOST"`
	Port         int    `mapstructure:"PORT"`
	User         string `mapstructure:"USER"`
	Password     string `mapstructure:"PASSWORD"`
	Name         string `mapstructure:"NAME"`
	SSLMode      string `mapstructure:"SSL_MODE"`
	MaxOpenConns int    `mapstructure:"MAX_OPEN_CONNS"`
	MaxIdleConns int    `mapstructure:"MAX_IDLE_CONNS"`
	MaxLifetime  time.Duration `mapstructure:"MAX_LIFETIME"`
}

// DSN returns the data source name for connecting to the database
func (c *DatabaseConfig) DSN() string {
	if c.URL != "" {
		return c.URL
	}
	return fmt.Sprintf(
		"host=%s port=%d user=%s password=%s dbname=%s sslmode=%s",
		c.Host, c.Port, c.User, c.Password, c.Name, c.SSLMode,
	)
}

// RedisConfig holds Redis configuration
type RedisConfig struct {
	URL      string `mapstructure:"REDIS_URL"`
	Host     string `mapstructure:"REDIS_HOST"`
	Port     int    `mapstructure:"REDIS_PORT"`
	Password string `mapstructure:"REDIS_PASSWORD"`
	DB       int    `mapstructure:"REDIS_DB"`
}

// Address returns the Redis address
func (c *RedisConfig) Address() string {
	if c.URL != "" {
		return c.URL
	}
	return fmt.Sprintf("%s:%d", c.Host, c.Port)
}

// AuthConfig holds authentication configuration
type AuthConfig struct {
	JWTSecret           string        `mapstructure:"JWT_SECRET"`
	JWTExpiryMinutes    int           `mapstructure:"JWT_EXPIRY_MINUTES"`
	RefreshExpiryDays   int           `mapstructure:"REFRESH_EXPIRY_DAYS"`
	GoogleClientID      string        `mapstructure:"GOOGLE_CLIENT_ID"`
	GoogleClientSecret  string        `mapstructure:"GOOGLE_CLIENT_SECRET"`
	AppleClientID       string        `mapstructure:"APPLE_CLIENT_ID"`
	AppleTeamID         string        `mapstructure:"APPLE_TEAM_ID"`
	AppleKeyID          string        `mapstructure:"APPLE_KEY_ID"`
	ApplePrivateKey     string        `mapstructure:"APPLE_PRIVATE_KEY"`
	MicrosoftClientID   string        `mapstructure:"MICROSOFT_CLIENT_ID"`
	MicrosoftSecret     string        `mapstructure:"MICROSOFT_CLIENT_SECRET"`
}

// JWTExpiry returns the JWT expiry duration
func (c *AuthConfig) JWTExpiry() time.Duration {
	return time.Duration(c.JWTExpiryMinutes) * time.Minute
}

// RefreshExpiry returns the refresh token expiry duration
func (c *AuthConfig) RefreshExpiry() time.Duration {
	return time.Duration(c.RefreshExpiryDays) * 24 * time.Hour
}

// LLMConfig holds LLM provider configuration
type LLMConfig struct {
	DefaultProvider string `mapstructure:"LLM_DEFAULT_PROVIDER"`
	AnthropicAPIKey string `mapstructure:"ANTHROPIC_API_KEY"`
	GoogleAPIKey    string `mapstructure:"GOOGLE_AI_API_KEY"`
	OpenAIAPIKey    string `mapstructure:"OPENAI_API_KEY"`
	OllamaHost      string `mapstructure:"OLLAMA_HOST"`
	OllamaModel     string `mapstructure:"OLLAMA_MODEL"`
}

// Load loads configuration from environment variables and config files
func Load() (*Config, error) {
	v := viper.New()

	// Set defaults
	setDefaults(v)

	// Read from environment variables
	v.AutomaticEnv()
	v.SetEnvKeyReplacer(strings.NewReplacer(".", "_"))

	// Bind common environment variable names used by Railway/PaaS platforms
	v.BindEnv("Databases.Shared.URL", "SHARED_DB_URL", "DATABASE_URL")
	v.BindEnv("Databases.Tasks.URL", "TASKS_DB_URL", "DATABASE_URL")
	v.BindEnv("Databases.Projects.URL", "PROJECTS_DB_URL", "DATABASE_URL")
	v.BindEnv("Redis.URL", "REDIS_URL")
	v.BindEnv("Auth.JWTSecret", "JWT_SECRET")
	v.BindEnv("Server.Port", "PORT")

	// Try to read from config file
	v.SetConfigName("config")
	v.SetConfigType("yaml")
	v.AddConfigPath(".")
	v.AddConfigPath("./config")
	v.AddConfigPath("/etc/flow/")

	// Ignore error if config file doesn't exist
	_ = v.ReadInConfig()

	var config Config
	if err := v.Unmarshal(&config); err != nil {
		return nil, fmt.Errorf("failed to unmarshal config: %w", err)
	}

	// Validate required fields
	if err := validate(&config); err != nil {
		return nil, err
	}

	return &config, nil
}

// LoadForService loads configuration for a specific service
func LoadForService(service string) (*Config, error) {
	config, err := Load()
	if err != nil {
		return nil, err
	}

	// Service-specific adjustments can be made here
	return config, nil
}

func setDefaults(v *viper.Viper) {
	// Server defaults
	v.SetDefault("Server.Host", "0.0.0.0")
	v.SetDefault("Server.Port", 8080)
	v.SetDefault("Server.ShutdownTimeout", 10*time.Second)
	v.SetDefault("Server.Environment", "development")

	// Database defaults
	v.SetDefault("Databases.Shared.Host", "localhost")
	v.SetDefault("Databases.Shared.Port", 5432)
	v.SetDefault("Databases.Shared.SSLMode", "disable")
	v.SetDefault("Databases.Shared.MaxOpenConns", 25)
	v.SetDefault("Databases.Shared.MaxIdleConns", 5)
	v.SetDefault("Databases.Shared.MaxLifetime", 5*time.Minute)

	v.SetDefault("Databases.Tasks.Host", "localhost")
	v.SetDefault("Databases.Tasks.Port", 5433)
	v.SetDefault("Databases.Tasks.SSLMode", "disable")
	v.SetDefault("Databases.Tasks.MaxOpenConns", 25)
	v.SetDefault("Databases.Tasks.MaxIdleConns", 5)

	v.SetDefault("Databases.Projects.Host", "localhost")
	v.SetDefault("Databases.Projects.Port", 5434)
	v.SetDefault("Databases.Projects.SSLMode", "disable")
	v.SetDefault("Databases.Projects.MaxOpenConns", 25)
	v.SetDefault("Databases.Projects.MaxIdleConns", 5)

	// Redis defaults
	v.SetDefault("Redis.Host", "localhost")
	v.SetDefault("Redis.Port", 6379)
	v.SetDefault("Redis.DB", 0)

	// Auth defaults
	v.SetDefault("Auth.JWTExpiryMinutes", 15)
	v.SetDefault("Auth.RefreshExpiryDays", 7)

	// LLM defaults
	v.SetDefault("LLM.DefaultProvider", "anthropic")
	v.SetDefault("LLM.OllamaHost", "http://localhost:11434")
	v.SetDefault("LLM.OllamaModel", "llama3.1:8b")
}

func validate(config *Config) error {
	// In production, certain fields are required
	if config.Server.Environment == "production" {
		if config.Auth.JWTSecret == "" {
			return fmt.Errorf("JWT_SECRET is required in production")
		}
	}
	return nil
}

// IsDevelopment returns true if running in development mode
func (c *Config) IsDevelopment() bool {
	return c.Server.Environment == "development"
}

// IsProduction returns true if running in production mode
func (c *Config) IsProduction() bool {
	return c.Server.Environment == "production"
}
