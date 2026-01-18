package tasks

import (
	"time"

	"github.com/gofiber/fiber/v2"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/csaptu/flow/common/dto"
	"github.com/csaptu/flow/pkg/config"
	"github.com/csaptu/flow/pkg/httputil"
	"github.com/csaptu/flow/pkg/middleware"
)

// AuthHandler handles authentication endpoints for the tasks service
type AuthHandler struct {
	db     *pgxpool.Pool
	config *config.Config
}

// AuthResponse represents the authentication response
type AuthResponse struct {
	User         dto.UserResponse `json:"user"`
	AccessToken  string           `json:"access_token"`
	RefreshToken string           `json:"refresh_token"`
	ExpiresAt    time.Time        `json:"expires_at"`
}

// NewAuthHandler creates a new auth handler
func NewAuthHandler(db *pgxpool.Pool, cfg *config.Config) *AuthHandler {
	return &AuthHandler{
		db:     db,
		config: cfg,
	}
}

// DevLoginRequest represents a dev login request
type DevLoginRequest struct {
	Email string `json:"email"`
}

// Dev accounts that can bypass password
var devAccounts = map[string]string{
	"tupham@prepedu.com": "Tu Pham",
	"alice@prepedu.com":  "Alice",
}

// DevLogin handles passwordless login for dev accounts (dev/debug only)
// This is a simplified auth flow that doesn't require the shared database
func (h *AuthHandler) DevLogin(c *fiber.Ctx) error {
	var req DevLoginRequest
	if err := c.BodyParser(&req); err != nil {
		return httputil.BadRequest(c, "invalid request body")
	}

	// Check if email is a dev account
	name, ok := devAccounts[req.Email]
	if !ok {
		return httputil.Unauthorized(c, "not a dev account")
	}

	// Use deterministic UUID based on email for consistent dev login
	userID := uuid.NewSHA1(uuid.NameSpaceURL, []byte("dev-user:"+req.Email))

	// Auto-migrate: In dev mode, if this user has no tasks but tasks exist with other user_ids,
	// adopt those tasks. This handles the transition from the old arbitrary user_id approach
	// to the new deterministic user_id approach.
	if h.config.IsDevelopment() {
		var hasOwnTasks bool
		_ = h.db.QueryRow(c.Context(),
			`SELECT EXISTS(SELECT 1 FROM tasks WHERE user_id = $1 AND deleted_at IS NULL)`,
			userID,
		).Scan(&hasOwnTasks)

		if !hasOwnTasks {
			// User has no tasks - adopt all existing tasks (dev convenience)
			_, _ = h.db.Exec(c.Context(),
				`UPDATE tasks SET user_id = $1 WHERE deleted_at IS NULL`,
				userID,
			)
		}
	}

	// Generate access token with longer expiry for dev convenience
	accessToken, expiresAt, err := middleware.GenerateAccessToken(
		userID, req.Email, h.config.Auth.JWTSecret, h.config.Auth.JWTExpiry(),
	)
	if err != nil {
		return httputil.InternalError(c, "failed to generate access token")
	}

	// Generate refresh token (not stored, just for API compatibility)
	refreshToken, _, err := middleware.GenerateRefreshToken(
		userID, req.Email, h.config.Auth.JWTSecret, h.config.Auth.RefreshExpiry(),
	)
	if err != nil {
		return httputil.InternalError(c, "failed to generate refresh token")
	}

	now := time.Now().Format(time.RFC3339)
	return httputil.Success(c, AuthResponse{
		User: dto.UserResponse{
			ID:            userID.String(),
			Email:         req.Email,
			EmailVerified: true,
			Name:          name,
			CreatedAt:     now,
			UpdatedAt:     now,
		},
		AccessToken:  accessToken,
		RefreshToken: refreshToken,
		ExpiresAt:    expiresAt,
	})
}
