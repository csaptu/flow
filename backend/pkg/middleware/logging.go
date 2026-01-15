package middleware

import (
	"time"

	"github.com/gofiber/fiber/v2"
	"github.com/google/uuid"
	"github.com/rs/zerolog"
	"github.com/rs/zerolog/log"
)

// RequestLogger creates a logging middleware
func RequestLogger() fiber.Handler {
	return func(c *fiber.Ctx) error {
		start := time.Now()

		// Generate request ID if not present
		requestID := c.Get("X-Request-ID")
		if requestID == "" {
			requestID = uuid.New().String()
		}
		c.Set("X-Request-ID", requestID)
		c.Locals("requestID", requestID)

		// Process request
		err := c.Next()

		// Calculate latency
		latency := time.Since(start)

		// Get status code
		status := c.Response().StatusCode()

		// Build log event
		var event *zerolog.Event
		if status >= 500 {
			event = log.Error()
		} else if status >= 400 {
			event = log.Warn()
		} else {
			event = log.Info()
		}

		// Add request details
		event.
			Str("request_id", requestID).
			Str("method", c.Method()).
			Str("path", c.Path()).
			Int("status", status).
			Dur("latency", latency).
			Str("ip", c.IP()).
			Str("user_agent", c.Get("User-Agent"))

		// Add user ID if authenticated
		if userID, ok := c.Locals("userID").(uuid.UUID); ok && userID != uuid.Nil {
			event.Str("user_id", userID.String())
		}

		// Add error if present
		if err != nil {
			event.Err(err)
		}

		// Log the request
		event.Msg("request")

		return err
	}
}

// Recovery creates a panic recovery middleware
func Recovery() fiber.Handler {
	return func(c *fiber.Ctx) error {
		defer func() {
			if r := recover(); r != nil {
				requestID, _ := c.Locals("requestID").(string)

				log.Error().
					Str("request_id", requestID).
					Interface("panic", r).
					Str("path", c.Path()).
					Msg("panic recovered")

				// Return 500 error
				_ = c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
					"success": false,
					"error": fiber.Map{
						"code":    "INTERNAL_ERROR",
						"message": "internal server error",
					},
				})
			}
		}()

		return c.Next()
	}
}

// RequestID middleware adds a unique request ID to each request
func RequestID() fiber.Handler {
	return func(c *fiber.Ctx) error {
		requestID := c.Get("X-Request-ID")
		if requestID == "" {
			requestID = uuid.New().String()
		}
		c.Set("X-Request-ID", requestID)
		c.Locals("requestID", requestID)
		return c.Next()
	}
}

// GetRequestID extracts the request ID from context
func GetRequestID(c *fiber.Ctx) string {
	requestID, _ := c.Locals("requestID").(string)
	return requestID
}

// LoggerWithFields creates a logger with predefined fields from context
func LoggerWithFields(c *fiber.Ctx) zerolog.Logger {
	requestID := GetRequestID(c)
	userID, _ := c.Locals("userID").(uuid.UUID)

	logger := log.With().
		Str("request_id", requestID)

	if userID != uuid.Nil {
		logger = logger.Str("user_id", userID.String())
	}

	return logger.Logger()
}
