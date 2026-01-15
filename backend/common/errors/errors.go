package errors

import (
	"errors"
	"fmt"
	"net/http"
)

// Standard error types for the application
var (
	// ErrNotFound is returned when a resource is not found
	ErrNotFound = errors.New("resource not found")

	// ErrAlreadyExists is returned when trying to create a duplicate resource
	ErrAlreadyExists = errors.New("resource already exists")

	// ErrUnauthorized is returned when authentication fails
	ErrUnauthorized = errors.New("unauthorized")

	// ErrForbidden is returned when the user doesn't have permission
	ErrForbidden = errors.New("forbidden")

	// ErrBadRequest is returned when the request is malformed
	ErrBadRequest = errors.New("bad request")

	// ErrValidation is returned when validation fails
	ErrValidation = errors.New("validation error")

	// ErrInternal is returned for internal server errors
	ErrInternal = errors.New("internal server error")

	// ErrConflict is returned when there's a conflict (e.g., version mismatch)
	ErrConflict = errors.New("conflict")

	// ErrRateLimit is returned when rate limit is exceeded
	ErrRateLimit = errors.New("rate limit exceeded")

	// ErrServiceUnavailable is returned when a dependent service is unavailable
	ErrServiceUnavailable = errors.New("service unavailable")
)

// Task-specific errors
var (
	// ErrTaskDepthExceeded is returned when trying to create a task too deep in hierarchy
	ErrTaskDepthExceeded = errors.New("task depth cannot exceed 1 (max 2 layers)")

	// ErrTaskNotFound is returned when a task is not found
	ErrTaskNotFound = errors.New("task not found")

	// ErrInvalidParent is returned when the parent task is invalid
	ErrInvalidParent = errors.New("invalid parent task")
)

// Project-specific errors
var (
	// ErrProjectNotFound is returned when a project is not found
	ErrProjectNotFound = errors.New("project not found")

	// ErrWBSNodeNotFound is returned when a WBS node is not found
	ErrWBSNodeNotFound = errors.New("WBS node not found")

	// ErrCyclicDependency is returned when adding a dependency would create a cycle
	ErrCyclicDependency = errors.New("cyclic dependency detected")

	// ErrCrossProjectDependency is returned when trying to create dependency across projects
	ErrCrossProjectDependency = errors.New("dependencies must be within the same project")

	// ErrInvalidDependencyType is returned when the dependency type is invalid
	ErrInvalidDependencyType = errors.New("invalid dependency type")

	// ErrNotProjectMember is returned when user is not a member of the project
	ErrNotProjectMember = errors.New("user is not a member of this project")

	// ErrInsufficientPermission is returned when user lacks required role
	ErrInsufficientPermission = errors.New("insufficient permission for this action")
)

// Auth-specific errors
var (
	// ErrInvalidCredentials is returned when login credentials are wrong
	ErrInvalidCredentials = errors.New("invalid email or password")

	// ErrTokenExpired is returned when a JWT token has expired
	ErrTokenExpired = errors.New("token expired")

	// ErrInvalidToken is returned when a JWT token is invalid
	ErrInvalidToken = errors.New("invalid token")

	// ErrRefreshTokenRevoked is returned when trying to use a revoked refresh token
	ErrRefreshTokenRevoked = errors.New("refresh token has been revoked")

	// ErrEmailNotVerified is returned when email verification is required
	ErrEmailNotVerified = errors.New("email not verified")

	// ErrOAuthProviderError is returned when OAuth provider returns an error
	ErrOAuthProviderError = errors.New("OAuth provider error")
)

// AI-specific errors
var (
	// ErrAIServiceUnavailable is returned when AI service is not available
	ErrAIServiceUnavailable = errors.New("AI service unavailable")

	// ErrAIRateLimit is returned when AI rate limit is exceeded
	ErrAIRateLimit = errors.New("AI rate limit exceeded for your plan")

	// ErrAIFeatureNotAvailable is returned when AI feature is not in user's plan
	ErrAIFeatureNotAvailable = errors.New("AI feature not available in your plan")
)

// AppError represents an application error with additional context
type AppError struct {
	Err        error
	Message    string
	StatusCode int
	Details    map[string]interface{}
}

// Error implements the error interface
func (e *AppError) Error() string {
	if e.Message != "" {
		return e.Message
	}
	return e.Err.Error()
}

// Unwrap returns the wrapped error
func (e *AppError) Unwrap() error {
	return e.Err
}

// New creates a new AppError
func New(err error, message string, statusCode int) *AppError {
	return &AppError{
		Err:        err,
		Message:    message,
		StatusCode: statusCode,
	}
}

// NewWithDetails creates a new AppError with additional details
func NewWithDetails(err error, message string, statusCode int, details map[string]interface{}) *AppError {
	return &AppError{
		Err:        err,
		Message:    message,
		StatusCode: statusCode,
		Details:    details,
	}
}

// Wrap wraps an error with additional context
func Wrap(err error, message string) *AppError {
	return &AppError{
		Err:        err,
		Message:    fmt.Sprintf("%s: %v", message, err),
		StatusCode: http.StatusInternalServerError,
	}
}

// NotFound creates a not found error
func NotFound(resource string) *AppError {
	return &AppError{
		Err:        ErrNotFound,
		Message:    fmt.Sprintf("%s not found", resource),
		StatusCode: http.StatusNotFound,
	}
}

// BadRequest creates a bad request error
func BadRequest(message string) *AppError {
	return &AppError{
		Err:        ErrBadRequest,
		Message:    message,
		StatusCode: http.StatusBadRequest,
	}
}

// ValidationError creates a validation error with field details
func ValidationError(message string, fields map[string]string) *AppError {
	details := make(map[string]interface{})
	for k, v := range fields {
		details[k] = v
	}
	return &AppError{
		Err:        ErrValidation,
		Message:    message,
		StatusCode: http.StatusBadRequest,
		Details:    details,
	}
}

// Unauthorized creates an unauthorized error
func Unauthorized(message string) *AppError {
	if message == "" {
		message = "authentication required"
	}
	return &AppError{
		Err:        ErrUnauthorized,
		Message:    message,
		StatusCode: http.StatusUnauthorized,
	}
}

// Forbidden creates a forbidden error
func Forbidden(message string) *AppError {
	if message == "" {
		message = "access denied"
	}
	return &AppError{
		Err:        ErrForbidden,
		Message:    message,
		StatusCode: http.StatusForbidden,
	}
}

// Internal creates an internal server error
func Internal(message string) *AppError {
	if message == "" {
		message = "internal server error"
	}
	return &AppError{
		Err:        ErrInternal,
		Message:    message,
		StatusCode: http.StatusInternalServerError,
	}
}

// IsNotFound checks if an error is a not found error
func IsNotFound(err error) bool {
	return errors.Is(err, ErrNotFound) ||
		errors.Is(err, ErrTaskNotFound) ||
		errors.Is(err, ErrProjectNotFound) ||
		errors.Is(err, ErrWBSNodeNotFound)
}

// IsUnauthorized checks if an error is an unauthorized error
func IsUnauthorized(err error) bool {
	return errors.Is(err, ErrUnauthorized) ||
		errors.Is(err, ErrInvalidCredentials) ||
		errors.Is(err, ErrTokenExpired) ||
		errors.Is(err, ErrInvalidToken)
}

// HTTPStatusCode returns the appropriate HTTP status code for an error
func HTTPStatusCode(err error) int {
	var appErr *AppError
	if errors.As(err, &appErr) {
		return appErr.StatusCode
	}

	switch {
	case IsNotFound(err):
		return http.StatusNotFound
	case IsUnauthorized(err):
		return http.StatusUnauthorized
	case errors.Is(err, ErrForbidden), errors.Is(err, ErrInsufficientPermission), errors.Is(err, ErrNotProjectMember):
		return http.StatusForbidden
	case errors.Is(err, ErrBadRequest), errors.Is(err, ErrValidation), errors.Is(err, ErrTaskDepthExceeded):
		return http.StatusBadRequest
	case errors.Is(err, ErrConflict), errors.Is(err, ErrCyclicDependency):
		return http.StatusConflict
	case errors.Is(err, ErrRateLimit), errors.Is(err, ErrAIRateLimit):
		return http.StatusTooManyRequests
	case errors.Is(err, ErrServiceUnavailable), errors.Is(err, ErrAIServiceUnavailable):
		return http.StatusServiceUnavailable
	default:
		return http.StatusInternalServerError
	}
}
