package auth

import (
	"context"
	"crypto/rand"
	"encoding/json"
	"fmt"
	"math/big"
	"time"

	"github.com/gofiber/fiber/v2"
	"github.com/google/uuid"
	"github.com/csaptu/flow/pkg/httputil"
	"golang.org/x/crypto/bcrypt"
)

const (
	verifyCodeLength       = 6
	verifyCodeExpiry       = 10 * time.Minute
	maxRegisterPerHour     = 5
	maxRegisterAttempts    = 5
)

// PendingRegistration stores registration data while awaiting email verification
type PendingRegistration struct {
	Email        string `json:"email"`
	PasswordHash string `json:"password_hash"`
	Name         string `json:"name"`
	Code         string `json:"code"`
	CreatedAt    int64  `json:"created_at"`
}

// VerifyRegistrationRequest represents the verification request
type VerifyRegistrationRequest struct {
	Email string `json:"email"`
	Code  string `json:"code"`
}

// generateVerifyCode generates a random 6-digit code
func generateVerifyCode() (string, error) {
	max := big.NewInt(1000000)
	n, err := rand.Int(rand.Reader, max)
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("%06d", n.Int64()), nil
}

// RegisterWithVerification handles user registration with email verification
func (h *Handler) RegisterWithVerification(c *fiber.Ctx) error {
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

	// Rate limiting
	rateLimitKey := fmt.Sprintf("register_rate:%s", req.Email)
	count, _ := h.redis.Incr(c.Context(), rateLimitKey).Result()
	if count == 1 {
		h.redis.Expire(c.Context(), rateLimitKey, time.Hour)
	}
	if count > int64(maxRegisterPerHour) {
		return httputil.TooManyRequests(c, "too many registration attempts, please try again later")
	}

	// Generate verification code
	code, err := generateVerifyCode()
	if err != nil {
		return httputil.InternalError(c, "failed to generate verification code")
	}

	// Hash password
	hashedPassword, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
	if err != nil {
		return httputil.InternalError(c, "failed to process registration")
	}

	// Store pending registration in Redis
	pending := PendingRegistration{
		Email:        req.Email,
		PasswordHash: string(hashedPassword),
		Name:         req.Name,
		Code:         code,
		CreatedAt:    time.Now().Unix(),
	}

	pendingJSON, _ := json.Marshal(pending)
	pendingKey := fmt.Sprintf("pending_registration:%s", req.Email)
	h.redis.Set(c.Context(), pendingKey, pendingJSON, verifyCodeExpiry)

	// Initialize attempt counter
	attemptKey := fmt.Sprintf("register_attempts:%s", req.Email)
	h.redis.Set(c.Context(), attemptKey, 0, verifyCodeExpiry)

	// Send verification email
	if h.email != nil {
		go func() {
			ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
			defer cancel()
			_ = h.email.SendVerificationCode(ctx, req.Email, code)
		}()
	}

	return httputil.Success(c, fiber.Map{
		"message":    "Verification code sent to your email",
		"expires_in": int(verifyCodeExpiry.Seconds()),
	})
}

// VerifyRegistration completes registration after email verification
func (h *Handler) VerifyRegistration(c *fiber.Ctx) error {
	var req VerifyRegistrationRequest
	if err := c.BodyParser(&req); err != nil {
		return httputil.BadRequest(c, "invalid request body")
	}

	if req.Email == "" || req.Code == "" {
		return httputil.BadRequest(c, "email and code are required")
	}

	// Check attempt count
	attemptKey := fmt.Sprintf("register_attempts:%s", req.Email)
	attempts, _ := h.redis.Incr(c.Context(), attemptKey).Result()
	if attempts > int64(maxRegisterAttempts) {
		// Clean up
		h.redis.Del(c.Context(), fmt.Sprintf("pending_registration:%s", req.Email))
		h.redis.Del(c.Context(), attemptKey)
		return httputil.TooManyRequests(c, "too many attempts, please register again")
	}

	// Get pending registration
	pendingKey := fmt.Sprintf("pending_registration:%s", req.Email)
	pendingJSON, err := h.redis.Get(c.Context(), pendingKey).Result()
	if err != nil {
		return httputil.BadRequest(c, "no pending registration found or code expired")
	}

	var pending PendingRegistration
	if err := json.Unmarshal([]byte(pendingJSON), &pending); err != nil {
		return httputil.InternalError(c, "failed to process registration")
	}

	// Verify code
	if pending.Code != req.Code {
		remaining := maxRegisterAttempts - int(attempts)
		if remaining > 0 {
			return httputil.BadRequest(c, fmt.Sprintf("invalid code, %d attempts remaining", remaining))
		}
		return httputil.BadRequest(c, "invalid code")
	}

	// Check if email was registered while pending (race condition)
	var exists bool
	err = h.db.QueryRow(c.Context(),
		"SELECT EXISTS(SELECT 1 FROM users WHERE email = $1 AND deleted_at IS NULL)",
		req.Email,
	).Scan(&exists)
	if err != nil {
		return httputil.InternalError(c, "database error")
	}
	if exists {
		// Clean up Redis
		h.redis.Del(c.Context(), pendingKey)
		h.redis.Del(c.Context(), attemptKey)
		return httputil.Conflict(c, "email already registered")
	}

	// Create user
	userID := uuid.New()
	now := time.Now()

	_, err = h.db.Exec(c.Context(),
		`INSERT INTO users (id, email, password_hash, name, email_verified, created_at, updated_at)
		 VALUES ($1, $2, $3, $4, $5, $6, $7)`,
		userID, pending.Email, pending.PasswordHash, pending.Name, true, now, now,
	)
	if err != nil {
		return httputil.InternalError(c, "failed to create user")
	}

	// Clean up Redis
	h.redis.Del(c.Context(), pendingKey)
	h.redis.Del(c.Context(), attemptKey)

	// Generate tokens
	return h.issueTokensAndRespond(c, userID, pending.Email, pending.Name)
}

// ResendVerificationCode resends the verification code for pending registration
func (h *Handler) ResendVerificationCode(c *fiber.Ctx) error {
	var req struct {
		Email string `json:"email"`
	}
	if err := c.BodyParser(&req); err != nil {
		return httputil.BadRequest(c, "invalid request body")
	}

	if req.Email == "" {
		return httputil.BadRequest(c, "email is required")
	}

	// Rate limiting
	rateLimitKey := fmt.Sprintf("register_rate:%s", req.Email)
	count, _ := h.redis.Incr(c.Context(), rateLimitKey).Result()
	if count == 1 {
		h.redis.Expire(c.Context(), rateLimitKey, time.Hour)
	}
	if count > int64(maxRegisterPerHour) {
		return httputil.TooManyRequests(c, "too many attempts, please try again later")
	}

	// Get pending registration
	pendingKey := fmt.Sprintf("pending_registration:%s", req.Email)
	pendingJSON, err := h.redis.Get(c.Context(), pendingKey).Result()
	if err != nil {
		// Don't reveal if registration exists
		return httputil.Success(c, fiber.Map{
			"message":    "If a pending registration exists, a new code has been sent",
			"expires_in": int(verifyCodeExpiry.Seconds()),
		})
	}

	var pending PendingRegistration
	if err := json.Unmarshal([]byte(pendingJSON), &pending); err != nil {
		return httputil.InternalError(c, "failed to process request")
	}

	// Generate new code
	code, err := generateVerifyCode()
	if err != nil {
		return httputil.InternalError(c, "failed to generate code")
	}

	// Update pending registration with new code
	pending.Code = code
	pending.CreatedAt = time.Now().Unix()
	pendingJSON2, _ := json.Marshal(pending)
	h.redis.Set(c.Context(), pendingKey, pendingJSON2, verifyCodeExpiry)

	// Reset attempt counter
	attemptKey := fmt.Sprintf("register_attempts:%s", req.Email)
	h.redis.Set(c.Context(), attemptKey, 0, verifyCodeExpiry)

	// Send verification email
	if h.email != nil {
		go func() {
			ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
			defer cancel()
			_ = h.email.SendVerificationCode(ctx, req.Email, code)
		}()
	}

	return httputil.Success(c, fiber.Map{
		"message":    "Verification code sent to your email",
		"expires_in": int(verifyCodeExpiry.Seconds()),
	})
}
