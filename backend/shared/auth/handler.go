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
	"github.com/csaptu/flow/common/dto"
	"github.com/csaptu/flow/common/errors"
	"github.com/csaptu/flow/common/models"
	"github.com/csaptu/flow/pkg/config"
	"github.com/csaptu/flow/pkg/email"
	"github.com/csaptu/flow/pkg/httputil"
	"github.com/csaptu/flow/pkg/middleware"
	"github.com/csaptu/flow/pkg/oauth"
	"github.com/csaptu/flow/shared/repository"
	"golang.org/x/crypto/bcrypt"
)

// Handler handles authentication endpoints
type Handler struct {
	db     *pgxpool.Pool
	redis  *redis.Client
	config *config.Config
	email  *email.Client
}

// NewHandler creates a new auth handler
func NewHandler(db *pgxpool.Pool, redis *redis.Client, cfg *config.Config) *Handler {
	var emailClient *email.Client
	if cfg.Email.ResendAPIKey != "" {
		emailClient = email.NewClient(cfg.Email.ResendAPIKey, cfg.Email.From)
	}
	return &Handler{
		db:     db,
		redis:  redis,
		config: cfg,
		email:  emailClient,
	}
}

// RegisterRequest represents the registration request body
type RegisterRequest struct {
	Email           string `json:"email"`
	Password        string `json:"password"`
	PasswordConfirm string `json:"password_confirm"`
	Name            string `json:"name"`
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

	if req.Password != req.PasswordConfirm {
		return httputil.ValidationError(c, "validation failed", map[string]string{
			"password_confirm": "passwords do not match",
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

	resp := toUserResponse(&user)

	// Load AI preferences
	aiPrefs, err := repository.GetUserAIPreferencesMap(c.Context(), userID)
	if err == nil && aiPrefs != nil {
		resp.AIPreferences = aiPrefs
	}

	return httputil.Success(c, resp)
}

// UpdateProfileRequest represents profile update request
type UpdateProfileRequest struct {
	Name      *string `json:"name,omitempty"`
	AvatarURL *string `json:"avatar_url,omitempty"`
}

// UpdateProfile updates the current user's profile
func (h *Handler) UpdateProfile(c *fiber.Ctx) error {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		return httputil.Error(c, err)
	}

	var req UpdateProfileRequest
	if err := c.BodyParser(&req); err != nil {
		return httputil.BadRequest(c, "invalid request body")
	}

	// Build update query
	updates := []string{}
	args := []interface{}{}
	argNum := 1

	if req.Name != nil {
		if *req.Name == "" {
			return httputil.ValidationError(c, "validation failed", map[string]string{
				"name": "cannot be empty",
			})
		}
		updates = append(updates, "name = $"+string(rune('0'+argNum)))
		args = append(args, *req.Name)
		argNum++
	}

	if req.AvatarURL != nil {
		updates = append(updates, "avatar_url = $"+string(rune('0'+argNum)))
		args = append(args, *req.AvatarURL)
		argNum++
	}

	if len(updates) == 0 {
		return httputil.BadRequest(c, "no fields to update")
	}

	// Add updated_at and user_id
	updates = append(updates, "updated_at = NOW()")
	args = append(args, userID)

	query := "UPDATE users SET " + updates[0]
	for i := 1; i < len(updates); i++ {
		query += ", " + updates[i]
	}
	query += " WHERE id = $" + string(rune('0'+argNum)) + " AND deleted_at IS NULL"

	_, err = h.db.Exec(c.Context(), query, args...)
	if err != nil {
		return httputil.InternalError(c, "failed to update profile")
	}

	// Return updated user
	var user models.User
	err = h.db.QueryRow(c.Context(),
		`SELECT id, email, email_verified, name, avatar_url, created_at, updated_at
		 FROM users WHERE id = $1 AND deleted_at IS NULL`,
		userID,
	).Scan(&user.ID, &user.Email, &user.EmailVerified, &user.Name, &user.AvatarURL,
		&user.CreatedAt, &user.UpdatedAt)

	if err != nil {
		return httputil.InternalError(c, "failed to fetch updated profile")
	}

	return httputil.Success(c, toUserResponse(&user))
}

// UpdateAIPreferencesRequest represents AI preferences update request
type UpdateAIPreferencesRequest struct {
	AIPreferences map[string]string `json:"ai_preferences"`
}

// UpdateAIPreferences updates the current user's AI preferences
func (h *Handler) UpdateAIPreferences(c *fiber.Ctx) error {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		return httputil.Error(c, err)
	}

	var req UpdateAIPreferencesRequest
	if err := c.BodyParser(&req); err != nil {
		return httputil.BadRequest(c, "invalid request body")
	}

	if req.AIPreferences == nil {
		return httputil.BadRequest(c, "ai_preferences is required")
	}

	// Validate preference values (must be "auto" or "ask")
	// Note: "off" was removed - use "ask" (manual) instead
	validValues := map[string]bool{"auto": true, "ask": true}
	validKeys := map[string]bool{
		"clean_title":       true,
		"clean_description": true,
		"decompose":         true,
		"entity_extraction": true,
		"duplicate_check":   true,
		"complexity":        true,
		"smart_due_date":    true,
	}

	for key, value := range req.AIPreferences {
		if !validKeys[key] {
			return httputil.BadRequest(c, "invalid preference key: "+key)
		}
		if !validValues[value] {
			return httputil.BadRequest(c, "invalid preference value: "+value+" (must be auto or ask)")
		}
	}

	// Get current preferences and merge with updates
	currentPrefs, err := repository.GetUserAIPreferences(c.Context(), userID)
	if err != nil {
		return httputil.InternalError(c, "failed to get current preferences")
	}

	// Apply updates
	for key, value := range req.AIPreferences {
		switch key {
		case "clean_title":
			currentPrefs.CleanTitle = value
		case "clean_description":
			currentPrefs.CleanDescription = value
		case "decompose":
			currentPrefs.Decompose = value
		case "entity_extraction":
			currentPrefs.EntityExtraction = value
		case "duplicate_check":
			currentPrefs.DuplicateCheck = value
		case "complexity":
			currentPrefs.Complexity = value
		case "smart_due_date":
			currentPrefs.SmartDueDate = value
		}
	}

	// Save preferences
	if err := repository.UpdateUserAIPreferences(c.Context(), userID, currentPrefs); err != nil {
		return httputil.InternalError(c, "failed to update preferences")
	}

	// Return updated preferences map
	prefsMap := map[string]string{
		"clean_title":       currentPrefs.CleanTitle,
		"clean_description": currentPrefs.CleanDescription,
		"decompose":         currentPrefs.Decompose,
		"entity_extraction": currentPrefs.EntityExtraction,
		"duplicate_check":   currentPrefs.DuplicateCheck,
		"complexity":        currentPrefs.Complexity,
		"smart_due_date":    currentPrefs.SmartDueDate,
	}

	return httputil.Success(c, fiber.Map{"ai_preferences": prefsMap})
}

// GetAIPreferences returns the current user's AI preferences
func (h *Handler) GetAIPreferences(c *fiber.Ctx) error {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		return httputil.Error(c, err)
	}

	prefs, err := repository.GetUserAIPreferencesMap(c.Context(), userID)
	if err != nil {
		return httputil.InternalError(c, "failed to get preferences")
	}

	return httputil.Success(c, fiber.Map{"ai_preferences": prefs})
}

// GoogleOAuth handles Google OAuth login/registration
func (h *Handler) GoogleOAuth(c *fiber.Ctx) error {
	var req OAuthRequest
	if err := c.BodyParser(&req); err != nil {
		return httputil.BadRequest(c, "invalid request body")
	}

	if req.IDToken == "" {
		return httputil.BadRequest(c, "id_token is required")
	}

	// Check if Google OAuth is configured
	if h.config.Auth.GoogleClientID == "" {
		return httputil.ServiceUnavailable(c, "Google OAuth not configured")
	}

	// Try to verify as ID token first, then as access token
	var googleUser *oauth.GoogleUser
	var err error

	// First try ID token verification
	googleUser, err = oauth.VerifyGoogleIDToken(c.Context(), req.IDToken, h.config.Auth.GoogleClientID)
	if err != nil {
		// If ID token verification fails, try as access token
		googleUser, err = oauth.VerifyGoogleAccessToken(c.Context(), req.IDToken)
		if err != nil {
			return httputil.Unauthorized(c, "invalid Google token: "+err.Error())
		}
	}

	// Check if user already exists by Google ID
	var user models.User
	err = h.db.QueryRow(c.Context(),
		`SELECT id, email, email_verified, name, avatar_url, google_id, created_at, updated_at
		 FROM users WHERE google_id = $1 AND deleted_at IS NULL`,
		googleUser.GoogleID,
	).Scan(&user.ID, &user.Email, &user.EmailVerified, &user.Name, &user.AvatarURL,
		&user.GoogleID, &user.CreatedAt, &user.UpdatedAt)

	if err == pgx.ErrNoRows {
		// Check if email already exists (link account)
		err = h.db.QueryRow(c.Context(),
			`SELECT id, email, email_verified, name, avatar_url, google_id, created_at, updated_at
			 FROM users WHERE email = $1 AND deleted_at IS NULL`,
			googleUser.Email,
		).Scan(&user.ID, &user.Email, &user.EmailVerified, &user.Name, &user.AvatarURL,
			&user.GoogleID, &user.CreatedAt, &user.UpdatedAt)

		if err == pgx.ErrNoRows {
			// Create new user
			user = models.User{
				ID:            uuid.New(),
				Email:         googleUser.Email,
				EmailVerified: googleUser.EmailVerified,
				Name:          googleUser.Name,
				GoogleID:      &googleUser.GoogleID,
				CreatedAt:     time.Now(),
				UpdatedAt:     time.Now(),
			}
			if googleUser.Picture != "" {
				user.AvatarURL = &googleUser.Picture
			}

			_, err = h.db.Exec(c.Context(),
				`INSERT INTO users (id, email, email_verified, name, avatar_url, google_id, created_at, updated_at)
				 VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
				user.ID, user.Email, user.EmailVerified, user.Name, user.AvatarURL, user.GoogleID, user.CreatedAt, user.UpdatedAt,
			)
			if err != nil {
				return httputil.InternalError(c, "failed to create user")
			}
		} else if err != nil {
			return httputil.InternalError(c, "database error")
		} else {
			// Link Google account to existing user
			_, err = h.db.Exec(c.Context(),
				`UPDATE users SET google_id = $1, email_verified = $2, updated_at = $3 WHERE id = $4`,
				googleUser.GoogleID, true, time.Now(), user.ID,
			)
			if err != nil {
				return httputil.InternalError(c, "failed to link Google account")
			}
			user.GoogleID = &googleUser.GoogleID
			user.EmailVerified = true
		}
	} else if err != nil {
		return httputil.InternalError(c, "database error")
	}

	// Update last login
	_, _ = h.db.Exec(c.Context(),
		"UPDATE users SET last_login_at = $1 WHERE id = $2",
		time.Now(), user.ID,
	)

	// Generate tokens
	return h.issueTokensAndRespond(c, user.ID, user.Email, user.Name)
}

// AppleOAuth handles Apple OAuth login/registration
func (h *Handler) AppleOAuth(c *fiber.Ctx) error {
	var req OAuthRequest
	if err := c.BodyParser(&req); err != nil {
		return httputil.BadRequest(c, "invalid request body")
	}

	if req.IDToken == "" {
		return httputil.BadRequest(c, "id_token is required")
	}

	// Check if Apple OAuth is configured
	if h.config.Auth.AppleClientID == "" {
		return httputil.ServiceUnavailable(c, "Apple Sign-In not configured")
	}

	// Verify the Apple ID token
	appleUser, err := oauth.VerifyAppleIDToken(c.Context(), req.IDToken, h.config.Auth.AppleClientID)
	if err != nil {
		return httputil.Unauthorized(c, "invalid Apple token: "+err.Error())
	}

	// Check if user already exists by Apple ID
	var user models.User
	err = h.db.QueryRow(c.Context(),
		`SELECT id, email, email_verified, name, avatar_url, apple_id, created_at, updated_at
		 FROM users WHERE apple_id = $1 AND deleted_at IS NULL`,
		appleUser.AppleID,
	).Scan(&user.ID, &user.Email, &user.EmailVerified, &user.Name, &user.AvatarURL,
		&user.AppleID, &user.CreatedAt, &user.UpdatedAt)

	if err == pgx.ErrNoRows {
		// Check if email already exists (link account)
		// Note: Apple may provide a private relay email
		err = h.db.QueryRow(c.Context(),
			`SELECT id, email, email_verified, name, avatar_url, apple_id, created_at, updated_at
			 FROM users WHERE email = $1 AND deleted_at IS NULL`,
			appleUser.Email,
		).Scan(&user.ID, &user.Email, &user.EmailVerified, &user.Name, &user.AvatarURL,
			&user.AppleID, &user.CreatedAt, &user.UpdatedAt)

		if err == pgx.ErrNoRows {
			// Create new user
			// Note: Apple only provides name on first sign-in, so we extract from request
			name := "Apple User"
			if req.Nonce != "" {
				// Client may pass name in nonce field (common pattern)
				name = req.Nonce
			}

			user = models.User{
				ID:            uuid.New(),
				Email:         appleUser.Email,
				EmailVerified: appleUser.EmailVerified,
				Name:          name,
				AppleID:       &appleUser.AppleID,
				CreatedAt:     time.Now(),
				UpdatedAt:     time.Now(),
			}

			_, err = h.db.Exec(c.Context(),
				`INSERT INTO users (id, email, email_verified, name, apple_id, created_at, updated_at)
				 VALUES ($1, $2, $3, $4, $5, $6, $7)`,
				user.ID, user.Email, user.EmailVerified, user.Name, user.AppleID, user.CreatedAt, user.UpdatedAt,
			)
			if err != nil {
				return httputil.InternalError(c, "failed to create user")
			}
		} else if err != nil {
			return httputil.InternalError(c, "database error")
		} else {
			// Link Apple account to existing user
			_, err = h.db.Exec(c.Context(),
				`UPDATE users SET apple_id = $1, updated_at = $2 WHERE id = $3`,
				appleUser.AppleID, time.Now(), user.ID,
			)
			if err != nil {
				return httputil.InternalError(c, "failed to link Apple account")
			}
			user.AppleID = &appleUser.AppleID
		}
	} else if err != nil {
		return httputil.InternalError(c, "database error")
	}

	// Update last login
	_, _ = h.db.Exec(c.Context(),
		"UPDATE users SET last_login_at = $1 WHERE id = $2",
		time.Now(), user.ID,
	)

	// Generate tokens
	return h.issueTokensAndRespond(c, user.ID, user.Email, user.Name)
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

// DevLoginRequest represents a dev login request
type DevLoginRequest struct {
	Email string `json:"email"`
}

// Dev accounts that can bypass password
// Maps email -> display name
var devAccounts = map[string]string{
	"quangtu.pham@gmail.com": "Tu Pham",
	"tupham@prepedu.com":     "Tu Pham",
}

// Dev aliases for convenience (short name -> real email)
var devAliases = map[string]string{
	"tupham":  "quangtu.pham@gmail.com",
	"tu":      "quangtu.pham@gmail.com",
	"prepedu": "tupham@prepedu.com",
}

// DevLogin handles passwordless login for dev accounts (dev/debug only)
func (h *Handler) DevLogin(c *fiber.Ctx) error {
	var req DevLoginRequest
	if err := c.BodyParser(&req); err != nil {
		return httputil.BadRequest(c, "invalid request body")
	}

	// Check for alias first (e.g., "tupham" -> "quangtu.pham@gmail.com")
	email := req.Email
	if realEmail, ok := devAliases[email]; ok {
		email = realEmail
	}

	// Check if email is a dev account
	name, ok := devAccounts[email]
	if !ok {
		return httputil.Unauthorized(c, "not a dev account")
	}
	req.Email = email // Use resolved email

	// Find or create user
	var user models.User
	err := h.db.QueryRow(c.Context(),
		`SELECT id, email, email_verified, name, avatar_url, created_at, updated_at
		 FROM users WHERE email = $1 AND deleted_at IS NULL`,
		req.Email,
	).Scan(&user.ID, &user.Email, &user.EmailVerified, &user.Name, &user.AvatarURL,
		&user.CreatedAt, &user.UpdatedAt)

	if err == pgx.ErrNoRows {
		// Create user
		userID := uuid.New()
		now := time.Now()
		_, err = h.db.Exec(c.Context(),
			`INSERT INTO users (id, email, name, email_verified, created_at, updated_at)
			 VALUES ($1, $2, $3, $4, $5, $6)`,
			userID, req.Email, name, true, now, now,
		)
		if err != nil {
			return httputil.InternalError(c, "failed to create dev user")
		}
		user = models.User{
			ID:            userID,
			Email:         req.Email,
			Name:          name,
			EmailVerified: true,
			CreatedAt:     now,
			UpdatedAt:     now,
		}
	} else if err != nil {
		return httputil.InternalError(c, "database error")
	}

	// Update last login
	_, _ = h.db.Exec(c.Context(),
		"UPDATE users SET last_login_at = $1 WHERE id = $2",
		time.Now(), user.ID,
	)

	// Issue tokens
	return h.issueTokensAndRespond(c, user.ID, user.Email, user.Name)
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

	now := time.Now().Format(time.RFC3339)
	return httputil.Success(c, AuthResponse{
		User: dto.UserResponse{
			ID:            userID.String(),
			Email:         email,
			EmailVerified: false,
			Name:          name,
			CreatedAt:     now,
			UpdatedAt:     now,
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
