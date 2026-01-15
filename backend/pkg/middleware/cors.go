package middleware

import (
	"github.com/gofiber/fiber/v2"
	"github.com/gofiber/fiber/v2/middleware/cors"
)

// CORSConfig holds configuration for CORS middleware
type CORSConfig struct {
	AllowOrigins     string
	AllowMethods     string
	AllowHeaders     string
	AllowCredentials bool
	ExposeHeaders    string
	MaxAge           int
}

// DefaultCORSConfig returns default CORS configuration
func DefaultCORSConfig() CORSConfig {
	return CORSConfig{
		AllowOrigins:     "*",
		AllowMethods:     "GET,POST,PUT,PATCH,DELETE,OPTIONS",
		AllowHeaders:     "Origin,Content-Type,Accept,Authorization,X-Request-ID,X-Device-ID",
		AllowCredentials: true,
		ExposeHeaders:    "Content-Length,Content-Type,X-Request-ID",
		MaxAge:           86400, // 24 hours
	}
}

// CORS creates a CORS middleware with the given configuration
func CORS(config CORSConfig) fiber.Handler {
	return cors.New(cors.Config{
		AllowOrigins:     config.AllowOrigins,
		AllowMethods:     config.AllowMethods,
		AllowHeaders:     config.AllowHeaders,
		AllowCredentials: config.AllowCredentials,
		ExposeHeaders:    config.ExposeHeaders,
		MaxAge:           config.MaxAge,
	})
}

// DevelopmentCORS returns a CORS middleware suitable for development
func DevelopmentCORS() fiber.Handler {
	return cors.New(cors.Config{
		AllowOrigins:     "http://localhost:3000,http://localhost:8080,http://127.0.0.1:3000",
		AllowMethods:     "GET,POST,PUT,PATCH,DELETE,OPTIONS",
		AllowHeaders:     "Origin,Content-Type,Accept,Authorization,X-Request-ID,X-Device-ID",
		AllowCredentials: true,
		ExposeHeaders:    "Content-Length,Content-Type,X-Request-ID",
		MaxAge:           0, // Disable caching for development
	})
}

// ProductionCORS returns a CORS middleware suitable for production
func ProductionCORS(allowedOrigins string) fiber.Handler {
	return cors.New(cors.Config{
		AllowOrigins:     allowedOrigins,
		AllowMethods:     "GET,POST,PUT,PATCH,DELETE,OPTIONS",
		AllowHeaders:     "Origin,Content-Type,Accept,Authorization,X-Request-ID,X-Device-ID",
		AllowCredentials: true,
		ExposeHeaders:    "Content-Length,Content-Type,X-Request-ID",
		MaxAge:           86400, // 24 hours
	})
}
