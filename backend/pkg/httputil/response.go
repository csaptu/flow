package httputil

import (
	"github.com/gofiber/fiber/v2"
	"github.com/csaptu/flow/common/dto"
	"github.com/csaptu/flow/common/errors"
)

// JSON sends a JSON response with the given status code
func JSON(c *fiber.Ctx, status int, data interface{}) error {
	return c.Status(status).JSON(data)
}

// Success sends a successful JSON response
func Success(c *fiber.Ctx, data interface{}) error {
	return c.Status(fiber.StatusOK).JSON(dto.Success(data))
}

// SuccessWithMeta sends a successful JSON response with pagination metadata
func SuccessWithMeta(c *fiber.Ctx, data interface{}, meta *dto.APIMeta) error {
	return c.Status(fiber.StatusOK).JSON(dto.SuccessWithMeta(data, meta))
}

// Created sends a 201 Created response
func Created(c *fiber.Ctx, data interface{}) error {
	return c.Status(fiber.StatusCreated).JSON(dto.Success(data))
}

// NoContent sends a 204 No Content response
func NoContent(c *fiber.Ctx) error {
	return c.SendStatus(fiber.StatusNoContent)
}

// Error sends an error JSON response
func Error(c *fiber.Ctx, err error) error {
	statusCode := errors.HTTPStatusCode(err)

	var appErr *errors.AppError
	if errors.IsAppError(err, &appErr) {
		response := dto.APIResponse{
			Success: false,
			Error: &dto.APIError{
				Code:    errorCode(statusCode),
				Message: appErr.Message,
				Details: appErr.Details,
			},
		}
		return c.Status(statusCode).JSON(response)
	}

	return c.Status(statusCode).JSON(dto.Error(errorCode(statusCode), err.Error()))
}

// IsAppError checks if err is an AppError and extracts it
func IsAppError(err error, target **errors.AppError) bool {
	return errors.As(err, target)
}

// BadRequest sends a 400 Bad Request response
func BadRequest(c *fiber.Ctx, message string) error {
	return c.Status(fiber.StatusBadRequest).JSON(dto.Error("BAD_REQUEST", message))
}

// Unauthorized sends a 401 Unauthorized response
func Unauthorized(c *fiber.Ctx, message string) error {
	if message == "" {
		message = "authentication required"
	}
	return c.Status(fiber.StatusUnauthorized).JSON(dto.Error("UNAUTHORIZED", message))
}

// Forbidden sends a 403 Forbidden response
func Forbidden(c *fiber.Ctx, message string) error {
	if message == "" {
		message = "access denied"
	}
	return c.Status(fiber.StatusForbidden).JSON(dto.Error("FORBIDDEN", message))
}

// NotFound sends a 404 Not Found response
func NotFound(c *fiber.Ctx, resource string) error {
	message := "resource not found"
	if resource != "" {
		message = resource + " not found"
	}
	return c.Status(fiber.StatusNotFound).JSON(dto.Error("NOT_FOUND", message))
}

// Conflict sends a 409 Conflict response
func Conflict(c *fiber.Ctx, message string) error {
	return c.Status(fiber.StatusConflict).JSON(dto.Error("CONFLICT", message))
}

// ValidationError sends a 400 Bad Request response with validation details
func ValidationError(c *fiber.Ctx, message string, fields map[string]string) error {
	details := make(map[string]interface{})
	for k, v := range fields {
		details[k] = v
	}
	return c.Status(fiber.StatusBadRequest).JSON(dto.ErrorWithDetails("VALIDATION_ERROR", message, details))
}

// InternalError sends a 500 Internal Server Error response
func InternalError(c *fiber.Ctx, message string) error {
	if message == "" {
		message = "internal server error"
	}
	return c.Status(fiber.StatusInternalServerError).JSON(dto.Error("INTERNAL_ERROR", message))
}

// RateLimitExceeded sends a 429 Too Many Requests response
func RateLimitExceeded(c *fiber.Ctx) error {
	return c.Status(fiber.StatusTooManyRequests).JSON(dto.Error("RATE_LIMIT_EXCEEDED", "too many requests"))
}

// ServiceUnavailable sends a 503 Service Unavailable response
func ServiceUnavailable(c *fiber.Ctx, message string) error {
	if message == "" {
		message = "service temporarily unavailable"
	}
	return c.Status(fiber.StatusServiceUnavailable).JSON(dto.Error("SERVICE_UNAVAILABLE", message))
}

// PaymentRequired sends a 402 Payment Required response
func PaymentRequired(c *fiber.Ctx, message string) error {
	if message == "" {
		message = "payment required"
	}
	return c.Status(fiber.StatusPaymentRequired).JSON(dto.Error("PAYMENT_REQUIRED", message))
}

// errorCode maps HTTP status codes to error codes
func errorCode(status int) string {
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
		return "RATE_LIMIT_EXCEEDED"
	case fiber.StatusServiceUnavailable:
		return "SERVICE_UNAVAILABLE"
	default:
		return "INTERNAL_ERROR"
	}
}

// ParsePagination parses pagination parameters from query string
func ParsePagination(c *fiber.Ctx) dto.PaginationParams {
	page := c.QueryInt("page", 1)
	pageSize := c.QueryInt("page_size", 20)

	params := dto.PaginationParams{
		Page:     page,
		PageSize: pageSize,
	}
	params.Validate()
	return params
}

// BuildMeta builds pagination metadata
func BuildMeta(page, pageSize int, totalCount int64) *dto.APIMeta {
	totalPages := int(totalCount) / pageSize
	if int(totalCount)%pageSize > 0 {
		totalPages++
	}

	return &dto.APIMeta{
		Page:       page,
		PageSize:   pageSize,
		TotalCount: totalCount,
		TotalPages: totalPages,
	}
}
