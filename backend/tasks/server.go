package tasks

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
)

// Server represents the tasks service server
type Server struct {
	app    *fiber.App
	config *config.Config
	db     *pgxpool.Pool
	redis  *redis.Client
	llm    *llm.MultiClient
}

// NewServer creates a new tasks service server
func NewServer(cfg *config.Config) (*Server, error) {
	// Initialize database connection
	db, err := initDatabase(cfg.Databases.Tasks)
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
		AppName:               "flow-tasks-service",
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

	// All routes require authentication
	v1.Use(middleware.Auth(middleware.AuthConfig{
		JWTSecret: s.config.Auth.JWTSecret,
	}))

	// Task routes
	taskHandler := NewTaskHandler(s.db, s.llm)
	tasks := v1.Group("/tasks")
	tasks.Post("", taskHandler.Create)
	tasks.Get("", taskHandler.List)
	tasks.Get("/today", taskHandler.Today)
	tasks.Get("/inbox", taskHandler.Inbox)
	tasks.Get("/upcoming", taskHandler.Upcoming)
	tasks.Get("/completed", taskHandler.Completed)
	tasks.Get("/:id", taskHandler.GetByID)
	tasks.Put("/:id", taskHandler.Update)
	tasks.Delete("/:id", taskHandler.Delete)
	tasks.Post("/:id/complete", taskHandler.Complete)
	tasks.Post("/:id/uncomplete", taskHandler.Uncomplete)
	tasks.Post("/:id/children", taskHandler.CreateChild)
	tasks.Get("/:id/children", taskHandler.GetChildren)

	// AI features
	tasks.Post("/:id/ai/decompose", taskHandler.AIDecompose)
	tasks.Post("/:id/ai/clean", taskHandler.AIClean)

	// Sync endpoint
	v1.Post("/sync", taskHandler.Sync)

	// Group routes
	groups := v1.Group("/groups")
	groups.Post("", taskHandler.CreateGroup)
	groups.Get("", taskHandler.ListGroups)
	groups.Put("/:id", taskHandler.UpdateGroup)
	groups.Delete("/:id", taskHandler.DeleteGroup)
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
	if s.db != nil {
		s.db.Close()
	}
	if s.redis != nil {
		_ = s.redis.Close()
	}
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
