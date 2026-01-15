package shared

import (
	"context"
	"fmt"

	"github.com/gofiber/fiber/v2"
	"github.com/gofiber/fiber/v2/middleware/compress"
	"github.com/gofiber/fiber/v2/middleware/helmet"
	"github.com/gofiber/fiber/v2/middleware/recover"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/v9"
	"github.com/tupham/flow/common/dto"
	"github.com/tupham/flow/pkg/config"
	"github.com/tupham/flow/pkg/llm"
	"github.com/tupham/flow/pkg/middleware"
	"github.com/tupham/flow/shared/auth"
	"github.com/tupham/flow/shared/user"
)

// Server represents the shared service server
type Server struct {
	app    *fiber.App
	config *config.Config
	db     *pgxpool.Pool
	redis  *redis.Client
	llm    *llm.MultiClient
}

// NewServer creates a new shared service server
func NewServer(cfg *config.Config) (*Server, error) {
	// Initialize database connection
	db, err := initDatabase(cfg.Databases.Shared)
	if err != nil {
		return nil, fmt.Errorf("failed to connect to database: %w", err)
	}

	// Initialize Redis client
	redisClient, err := initRedis(cfg.Redis)
	if err != nil {
		return nil, fmt.Errorf("failed to connect to Redis: %w", err)
	}

	// Initialize LLM client
	llmClient, err := llm.NewMultiClient(llm.Config{
		DefaultProvider: llm.Provider(cfg.LLM.DefaultProvider),
		AnthropicAPIKey: cfg.LLM.AnthropicAPIKey,
		GoogleAPIKey:    cfg.LLM.GoogleAPIKey,
		OpenAIAPIKey:    cfg.LLM.OpenAIAPIKey,
		OllamaHost:      cfg.LLM.OllamaHost,
		OllamaModel:     cfg.LLM.OllamaModel,
	})
	if err != nil {
		// LLM client is optional, log warning but continue
		fmt.Printf("Warning: LLM client initialization failed: %v\n", err)
	}

	server := &Server{
		config: cfg,
		db:     db,
		redis:  redisClient,
		llm:    llmClient,
	}

	// Create Fiber app
	server.app = server.createApp()

	// Register routes
	server.registerRoutes()

	return server, nil
}

func (s *Server) createApp() *fiber.App {
	app := fiber.New(fiber.Config{
		AppName:               "flow-shared-service",
		DisableStartupMessage: true,
		ErrorHandler:          errorHandler,
	})

	// Global middleware
	app.Use(recover.New())
	app.Use(middleware.Recovery())
	app.Use(middleware.RequestLogger())
	app.Use(compress.New())
	app.Use(helmet.New())

	// CORS
	if s.config.IsDevelopment() {
		app.Use(middleware.DevelopmentCORS())
	} else {
		app.Use(middleware.ProductionCORS("https://flowapp.io,https://app.flowapp.io"))
	}

	return app
}

func (s *Server) registerRoutes() {
	// Health check
	s.app.Get("/health", s.healthCheck)

	// API v1
	v1 := s.app.Group("/api/v1")

	// Auth routes (public)
	authHandler := auth.NewHandler(s.db, s.redis, s.config)
	authRoutes := v1.Group("/auth")
	authRoutes.Post("/register", authHandler.Register)
	authRoutes.Post("/login", authHandler.Login)
	authRoutes.Post("/refresh", authHandler.Refresh)
	authRoutes.Post("/logout", authHandler.Logout)
	authRoutes.Post("/google", authHandler.GoogleOAuth)
	authRoutes.Post("/apple", authHandler.AppleOAuth)
	authRoutes.Post("/microsoft", authHandler.MicrosoftOAuth)

	// Protected routes
	protected := v1.Group("")
	protected.Use(middleware.Auth(middleware.AuthConfig{
		JWTSecret: s.config.Auth.JWTSecret,
		SkipPaths: []string{"/api/v1/auth"},
	}))

	// User routes
	userHandler := user.NewHandler(s.db)
	protected.Get("/auth/me", authHandler.Me)
	protected.Get("/users/:id", userHandler.GetByID)
	protected.Put("/users/:id", userHandler.Update)
	protected.Delete("/users/:id", userHandler.Delete)
}

func (s *Server) healthCheck(c *fiber.Ctx) error {
	services := make(map[string]string)

	// Check database
	if err := s.db.Ping(c.Context()); err != nil {
		services["database"] = "error"
	} else {
		services["database"] = "ok"
	}

	// Check Redis
	if err := s.redis.Ping(c.Context()).Err(); err != nil {
		services["redis"] = "error"
	} else {
		services["redis"] = "ok"
	}

	// Check LLM (optional)
	if s.llm != nil {
		services["llm"] = "ok"
	} else {
		services["llm"] = "not_configured"
	}

	status := "healthy"
	for _, v := range services {
		if v == "error" {
			status = "unhealthy"
			break
		}
	}

	return c.JSON(dto.HealthResponse{
		Status:   status,
		Version:  "1.0.0",
		Services: services,
	})
}

// Listen starts the HTTP server
func (s *Server) Listen(addr string) error {
	return s.app.Listen(addr)
}

// ShutdownWithContext gracefully shuts down the server
func (s *Server) ShutdownWithContext(ctx context.Context) error {
	// Close database connection
	if s.db != nil {
		s.db.Close()
	}

	// Close Redis connection
	if s.redis != nil {
		_ = s.redis.Close()
	}

	// Shutdown Fiber app
	return s.app.ShutdownWithContext(ctx)
}

func initDatabase(cfg config.DatabaseConfig) (*pgxpool.Pool, error) {
	poolConfig, err := pgxpool.ParseConfig(cfg.DSN())
	if err != nil {
		return nil, err
	}

	poolConfig.MaxConns = int32(cfg.MaxOpenConns)
	poolConfig.MinConns = int32(cfg.MaxIdleConns)
	poolConfig.MaxConnLifetime = cfg.MaxLifetime

	pool, err := pgxpool.NewWithConfig(context.Background(), poolConfig)
	if err != nil {
		return nil, err
	}

	// Test connection
	if err := pool.Ping(context.Background()); err != nil {
		return nil, err
	}

	return pool, nil
}

func initRedis(cfg config.RedisConfig) (*redis.Client, error) {
	opt, err := redis.ParseURL(cfg.Address())
	if err != nil {
		opt = &redis.Options{
			Addr:     fmt.Sprintf("%s:%d", cfg.Host, cfg.Port),
			Password: cfg.Password,
			DB:       cfg.DB,
		}
	}

	client := redis.NewClient(opt)

	// Test connection
	if err := client.Ping(context.Background()).Err(); err != nil {
		return nil, err
	}

	return client, nil
}

func errorHandler(c *fiber.Ctx, err error) error {
	code := fiber.StatusInternalServerError

	if e, ok := err.(*fiber.Error); ok {
		code = e.Code
	}

	return c.Status(code).JSON(dto.Error(
		errorCodeFromStatus(code),
		err.Error(),
	))
}

func errorCodeFromStatus(status int) string {
	switch status {
	case fiber.StatusBadRequest:
		return "BAD_REQUEST"
	case fiber.StatusUnauthorized:
		return "UNAUTHORIZED"
	case fiber.StatusForbidden:
		return "FORBIDDEN"
	case fiber.StatusNotFound:
		return "NOT_FOUND"
	case fiber.StatusConflict:
		return "CONFLICT"
	case fiber.StatusTooManyRequests:
		return "RATE_LIMIT"
	default:
		return "INTERNAL_ERROR"
	}
}
