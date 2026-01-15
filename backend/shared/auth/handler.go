package auth

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"time"

	"github.com/gofiber/fiber/v2"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/v9"
	"github.com/tupham/flow/common/dto"
	"github.com/tupham/flow/common/errors"
	"github.com/tupham/flow/common/models"
	"github.com/tupham/flow/pkg/config"
	"github.com/tupham/flow/pkg/httputil"
	"github.com/tupham/flow/pkg/middleware"
	"golang.org/x/crypto/bcrypt"
)

// Handler handles authentication endpoints
type Handler struct {
	db     *pgxpool.Pool
	redis  *redis.Client
	config *config.Config
}

// NewHandler creates a new auth handler
func NewHandler(db *pgxpool.Pool, redis *redis.Client, cfg *config.Config) *Handler {
	return &Handler{
		db:     db,
		redis:  redis,
		config: cfg,
	}
}

// RegisterRequest represents the registration request body
type RegisterRequest struct {
	Email    string `json:"email"`
	Password string `json:"password"`
	Name     string `json:"name"`
}

// LoginRequest represents the login request body
type LoginRequest struct {
	Email    string `json:"email"`
	Password string `json:"password"`
}

// RefreshRequest represents the token refresh request body
type RefreshRequest struct {
	RefreshToken string `json:"refresh_token"`
}

// OAuthRequest represents an OAuth login request
type OAuthRequest struct {
	IDToken  string `json:"id_token"`
	Code     string `json:"code,omitempty"`
	Nonce    string `json:"nonce,omitempty"`
	DeviceID string `json:"device_id,omitempty"`
}

// AuthResponse represents the authentication response
type AuthResponse struct {
	User         dto.UserResponse `json:"user"`
	AccessToken  string           `json:"access_token"`
	RefreshToken string           `json:"refresh_token"`
	ExpiresAt    time.Time        `json:"expires_at"`
}

// Register handles user registration
func (h *Handler) Register(c *fiber.Ctx) error {
	var req RegisterRequest
	if err := c.BodyParser(&req); err != nil {
		return httputil.BadRequest(c, "invalid request body")
	}

	// Validate input
	if req.Email == "" || req.Password == "" || req.Name == "" {
		return httputil.ValidationError(c, "validation failed", map[string]string{
			"email":    "required",
			"password": "required",
			"name":     "required",
		})
	}

	if len(req.Password) < 8 {
		return httputil.ValidationError(c, "validation failed", map[string]string{
			"password": "must be at least 8 characters",
		})
	}

	// Check if email already exists
	var exists bool
	err := h.db.QueryRow(c.Context(),
		"SELECT EXISTS(SELECT 1 FROM users WHERE email = $1 AND deleted_at IS NULL)",
		req.Email,
	).Scan(&exists)
	if err != nil {
		return httputil.InternalError(c, "database error")
	}
	if exists {
		return httputil.Conflict(c, "email already registered")
	}

	// Hash password
	hashedPassword, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
	if err != nil {
		return httputil.InternalError(c, "failed to hash password")
	}

	// Create user
	userID := uuid.New()
	hashedPwd := string(hashedPassword)
	now := time.Now()

	_, err = h.db.Exec(c.Context(),
		`INSERT INTO users (id, email, password_hash, name, email_verified, created_at, updated_at)
		 VALUES ($1, $2, $3, $4, $5, $6, $7)`,
		userID, req.Email, hashedPwd, req.Name, false, now, now,
	)
	if err != nil {
		return httputil.InternalError(c, "failed to create user")
	}

	// Generate tokens
	return h.issueTokensAndRespond(c, userID, req.Email, req.Name)
}

// Login handles user login
func (h *Handler) Login(c *fiber.Ctx) error {
	var req LoginRequest
	if err := c.BodyParser(&req); err != nil {
		return httputil.BadRequest(c, "invalid request body")
	}

	if req.Email == "" || req.Password == "" {
		return httputil.ValidationError(c, "validation failed", map[string]string{
			"email":    "required",
			"password": "required",
		})
	}

	// Get user by email
	var user models.User
	err := h.db.QueryRow(c.Context(),
		`SELECT id, email, password_hash, name, email_verified, avatar_url, created_at, updated_at
		 FROM users WHERE email = $1 AND deleted_at IS NULL`,
		req.Email,
	).Scan(&user.ID, &user.Email, &user.PasswordHash, &user.Name, &user.EmailVerified,
		&user.AvatarURL, &user.CreatedAt, &user.UpdatedAt)

	if err == pgx.ErrNoRows {
		return httputil.Unauthorized(c, "invalid email or password")
	}
	if err != nil {
		return httputil.InternalError(c, "database error")
	}

	// Verify password
	if user.PasswordHash == nil {
		return httputil.Unauthorized(c, "invalid email or password")
	}
	if err := bcrypt.CompareHashAndPassword([]byte(*user.PasswordHash), []byte(req.Password)); err != nil {
		return httputil.Unauthorized(c, "invalid email or password")
	}

	// Update last login
	_, _ = h.db.Exec(c.Context(),
		"UPDATE users SET last_login_at = $1 WHERE id = $2",
		time.Now(), user.ID,
	)

	// Generate tokens
	return h.issueTokensAndRespond(c, user.ID, user.Email, user.Name)
}

// Refresh handles token refresh
func (h *Handler) Refresh(c *fiber.Ctx) error {
	var req RefreshRequest
	if err := c.BodyParser(&req); err != nil {
		return httputil.BadRequest(c, "invalid request body")
	}

	if req.RefreshToken == "" {
		return httputil.BadRequest(c, "refresh_token is required")
	}

	// Hash the token to look up in database
	tokenHash := hashToken(req.RefreshToken)

	// Find and validate refresh token
	var userID uuid.UUID
	var email, name string
	var expiresAt time.Time
	var revokedAt *time.Time

	err := h.db.QueryRow(c.Context(),
		`SELECT rt.user_id, rt.expires_at, rt.revoked_at, u.email, u.name
		 FROM refresh_tokens rt
		 JOIN users u ON rt.user_id = u.id
		 WHERE rt.token_hash = $1 AND u.deleted_at IS NULL`,
		tokenHash,
	).Scan(&userID, &expiresAt, &revokedAt, &email, &name)

	if err == pgx.ErrNoRows {
		return httputil.Unauthorized(c, "invalid refresh token")
	}
	if err != nil {
		return httputil.InternalError(c, "database error")
	}

	// Check if token is revoked or expired
	if revokedAt != nil {
		return httputil.Unauthorized(c, "refresh token has been revoked")
	}
	if time.Now().After(expiresAt) {
		return httputil.Unauthorized(c, "refresh token has expired")
	}

	// Revoke the old refresh token (rotate)
	_, _ = h.db.Exec(c.Context(),
		"UPDATE refresh_tokens SET revoked_at = $1 WHERE token_hash = $2",
		time.Now(), tokenHash,
	)

	// Issue new tokens
	return h.issueTokensAndRespond(c, userID, email, name)
}

// Logout handles user logout
func (h *Handler) Logout(c *fiber.Ctx) error {
	var req RefreshRequest
	if err := c.BodyParser(&req); err != nil {
		// If no body, just return success (logout without token)
		return httputil.Success(c, map[string]string{"message": "logged out"})
	}

	if req.RefreshToken != "" {
		tokenHash := hashToken(req.RefreshToken)
		_, _ = h.db.Exec(c.Context(),
			"UPDATE refresh_tokens SET revoked_at = $1 WHERE token_hash = $2",
			time.Now(), tokenHash,
		)
	}

	return httputil.Success(c, map[string]string{"message": "logged out"})
}

// Me returns the current authenticated user
func (h *Handler) Me(c *fiber.Ctx) error {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		return httputil.Error(c, err)
	}

	var user models.User
	err = h.db.QueryRow(c.Context(),
		`SELECT id, email, email_verified, name, avatar_url, created_at, updated_at
		 FROM users WHERE id = $1 AND deleted_at IS NULL`,
		userID,
	).Scan(&user.ID, &user.Email, &user.EmailVerified, &user.Name, &user.AvatarURL,
		&user.CreatedAt, &user.UpdatedAt)

	if err == pgx.ErrNoRows {
		return httputil.Error(c, errors.NotFound("user"))
	}
	if err != nil {
		return httputil.InternalError(c, "database error")
	}

	return httputil.Success(c, toUserResponse(&user))
}

// GoogleOAuth handles Google OAuth login/registration
func (h *Handler) GoogleOAuth(c *fiber.Ctx) error {
	var req OAuthRequest
	if err := c.BodyParser(&req); err != nil {
		return httputil.BadRequest(c, "invalid request body")
	}

	// TODO: Verify Google ID token
	// For now, return not implemented
	return httputil.ServiceUnavailable(c, "Google OAuth not yet implemented")
}

// AppleOAuth handles Apple OAuth login/registration
func (h *Handler) AppleOAuth(c *fiber.Ctx) error {
	var req OAuthRequest
	if err := c.BodyParser(&req); err != nil {
		return httputil.BadRequest(c, "invalid request body")
	}

	// TODO: Verify Apple ID token
	return httputil.ServiceUnavailable(c, "Apple OAuth not yet implemented")
}

// MicrosoftOAuth handles Microsoft OAuth login/registration
func (h *Handler) MicrosoftOAuth(c *fiber.Ctx) error {
	var req OAuthRequest
	if err := c.BodyParser(&req); err != nil {
		return httputil.BadRequest(c, "invalid request body")
	}

	// TODO: Verify Microsoft ID token
	return httputil.ServiceUnavailable(c, "Microsoft OAuth not yet implemented")
}

// Helper methods

func (h *Handler) issueTokensAndRespond(c *fiber.Ctx, userID uuid.UUID, email, name string) error {
	// Generate access token
	accessToken, expiresAt, err := middleware.GenerateAccessToken(
		userID, email, h.config.Auth.JWTSecret, h.config.Auth.JWTExpiry(),
	)
	if err != nil {
		return httputil.InternalError(c, "failed to generate access token")
	}

	// Generate refresh token
	refreshToken, refreshExpiresAt, err := middleware.GenerateRefreshToken(
		userID, email, h.config.Auth.JWTSecret, h.config.Auth.RefreshExpiry(),
	)
	if err != nil {
		return httputil.InternalError(c, "failed to generate refresh token")
	}

	// Store refresh token hash in database
	tokenHash := hashToken(refreshToken)
	_, err = h.db.Exec(context.Background(),
		`INSERT INTO refresh_tokens (id, user_id, token_hash, expires_at, created_at)
		 VALUES ($1, $2, $3, $4, $5)`,
		uuid.New(), userID, tokenHash, refreshExpiresAt, time.Now(),
	)
	if err != nil {
		return httputil.InternalError(c, "failed to store refresh token")
	}

	return httputil.Success(c, AuthResponse{
		User: dto.UserResponse{
			ID:    userID.String(),
			Email: email,
			Name:  name,
		},
		AccessToken:  accessToken,
		RefreshToken: refreshToken,
		ExpiresAt:    expiresAt,
	})
}

func hashToken(token string) string {
	hash := sha256.Sum256([]byte(token))
	return hex.EncodeToString(hash[:])
}

func toUserResponse(u *models.User) dto.UserResponse {
	resp := dto.UserResponse{
		ID:            u.ID.String(),
		Email:         u.Email,
		EmailVerified: u.EmailVerified,
		Name:          u.Name,
		AvatarURL:     u.AvatarURL,
		CreatedAt:     u.CreatedAt.Format(time.RFC3339),
		UpdatedAt:     u.UpdatedAt.Format(time.RFC3339),
	}
	return resp
}
