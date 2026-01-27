package auth

import (
	"crypto/rand"
	"fmt"
	"math/big"
	"time"

	"github.com/gofiber/fiber/v2"
	"github.com/google/uuid"
	"github.com/csaptu/flow/pkg/httputil"
	"golang.org/x/crypto/bcrypt"
)

const (
	resetCodeLength     = 6
	resetCodeExpiry     = 10 * time.Minute
	maxResetPerHour     = 5
	maxResetPerDay      = 10
	maxVerifyAttempts   = 5
)

// ForgotPasswordRequest represents a password reset code request
type ForgotPasswordRequest struct {
	Email string `json:"email"`
}

// VerifyResetCodeRequest represents a code verification request
type VerifyResetCodeRequest struct {
	Email string `json:"email"`
	Code  string `json:"code"`
}

// ResetPasswordWithCodeRequest represents password reset with verified code
type ResetPasswordWithCodeRequest struct {
	Email       string `json:"email"`
	Code        string `json:"code"`
	NewPassword string `json:"new_password"`
}

// generateResetCode generates a random 6-digit code
func generateResetCode() (string, error) {
	max := big.NewInt(1000000) // 0-999999
	n, err := rand.Int(rand.Reader, max)
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("%06d", n.Int64()), nil
}

// ForgotPassword handles password reset code requests
// Rate limited: 5/hour, 10/day per email; 5/hour per IP
func (h *Handler) ForgotPassword(c *fiber.Ctx) error {
	var req ForgotPasswordRequest
	if err := c.BodyParser(&req); err != nil {
		return httputil.BadRequest(c, "invalid request body")
	}

	if req.Email == "" {
		return httputil.BadRequest(c, "email is required")
	}

	// Check if email service is configured
	if h.email == nil {
		return httputil.ServiceUnavailable(c, "email service not configured")
	}

	ip := c.IP()
	ctx := c.Context()

	// Rate limit by IP (5/hour)
	ipKey := fmt.Sprintf("reset_ip:%s", ip)
	ipCount, _ := h.redis.Get(ctx, ipKey).Int()
	if ipCount >= maxResetPerHour {
		return httputil.TooManyRequests(c, "too many reset requests, please try again later")
	}

	// Rate limit by email (5/hour, 10/day)
	emailHourKey := fmt.Sprintf("reset_email_hour:%s", req.Email)
	emailDayKey := fmt.Sprintf("reset_email_day:%s", req.Email)

	emailHourCount, _ := h.redis.Get(ctx, emailHourKey).Int()
	emailDayCount, _ := h.redis.Get(ctx, emailDayKey).Int()

	if emailHourCount >= maxResetPerHour {
		return httputil.TooManyRequests(c, "too many reset requests for this email, please try again later")
	}
	if emailDayCount >= maxResetPerDay {
		return httputil.TooManyRequests(c, "daily reset limit reached for this email, please try again tomorrow")
	}

	// Increment rate limit counters
	h.redis.Incr(ctx, ipKey)
	h.redis.Expire(ctx, ipKey, 1*time.Hour)

	h.redis.Incr(ctx, emailHourKey)
	h.redis.Expire(ctx, emailHourKey, 1*time.Hour)

	h.redis.Incr(ctx, emailDayKey)
	h.redis.Expire(ctx, emailDayKey, 24*time.Hour)

	// Check if user exists (silently continue if not for security)
	var userID uuid.UUID
	err := h.db.QueryRow(ctx,
		"SELECT id FROM users WHERE email = $1 AND deleted_at IS NULL",
		req.Email,
	).Scan(&userID)

	if err == nil {
		// User exists - generate and store code
		code, err := generateResetCode()
		if err != nil {
			return httputil.InternalError(c, "failed to generate reset code")
		}

		// Store code in Redis with expiry
		codeKey := fmt.Sprintf("reset_code:%s", req.Email)
		attemptsKey := fmt.Sprintf("reset_attempts:%s", req.Email)

		h.redis.Set(ctx, codeKey, code, resetCodeExpiry)
		h.redis.Del(ctx, attemptsKey) // Reset verification attempts

		// Send email with code
		if err := h.email.SendPasswordResetCode(ctx, req.Email, code); err != nil {
			// Log error but don't reveal to user
			fmt.Printf("Failed to send reset email: %v\n", err)
		}
	}

	// Always return success (security: don't reveal if email exists)
	return httputil.Success(c, map[string]interface{}{
		"message":    "If this email is registered, a verification code has been sent.",
		"expires_in": int(resetCodeExpiry.Seconds()),
	})
}

// VerifyResetCode verifies the 6-digit reset code
func (h *Handler) VerifyResetCode(c *fiber.Ctx) error {
	var req VerifyResetCodeRequest
	if err := c.BodyParser(&req); err != nil {
		return httputil.BadRequest(c, "invalid request body")
	}

	if req.Email == "" || req.Code == "" {
		return httputil.BadRequest(c, "email and code are required")
	}

	ctx := c.Context()

	// Check verification attempts (max 5)
	attemptsKey := fmt.Sprintf("reset_attempts:%s", req.Email)
	attempts, _ := h.redis.Get(ctx, attemptsKey).Int()
	if attempts >= maxVerifyAttempts {
		// Delete the code after too many attempts
		codeKey := fmt.Sprintf("reset_code:%s", req.Email)
		h.redis.Del(ctx, codeKey)
		return httputil.TooManyRequests(c, "too many verification attempts, please request a new code")
	}

	// Get stored code
	codeKey := fmt.Sprintf("reset_code:%s", req.Email)
	storedCode, err := h.redis.Get(ctx, codeKey).Result()
	if err != nil {
		// Increment attempts even for non-existent codes (security)
		h.redis.Incr(ctx, attemptsKey)
		h.redis.Expire(ctx, attemptsKey, resetCodeExpiry)
		return httputil.BadRequest(c, "invalid or expired code")
	}

	// Verify code
	if storedCode != req.Code {
		h.redis.Incr(ctx, attemptsKey)
		h.redis.Expire(ctx, attemptsKey, resetCodeExpiry)
		remaining := maxVerifyAttempts - attempts - 1
		return httputil.BadRequest(c, fmt.Sprintf("invalid code, %d attempts remaining", remaining))
	}

	// Code is valid - generate a short-lived token for password reset
	verifiedKey := fmt.Sprintf("reset_verified:%s", req.Email)
	h.redis.Set(ctx, verifiedKey, "1", 5*time.Minute) // 5 min to set new password

	return httputil.Success(c, map[string]interface{}{
		"message":    "Code verified successfully",
		"expires_in": 300, // 5 minutes to set new password
	})
}

// ResetPasswordWithCode resets password after code verification
func (h *Handler) ResetPasswordWithCode(c *fiber.Ctx) error {
	var req ResetPasswordWithCodeRequest
	if err := c.BodyParser(&req); err != nil {
		return httputil.BadRequest(c, "invalid request body")
	}

	if req.Email == "" || req.Code == "" || req.NewPassword == "" {
		return httputil.BadRequest(c, "email, code, and new_password are required")
	}

	if len(req.NewPassword) < 8 {
		return httputil.ValidationError(c, "validation failed", map[string]string{
			"new_password": "must be at least 8 characters",
		})
	}

	ctx := c.Context()

	// Check if code was verified
	verifiedKey := fmt.Sprintf("reset_verified:%s", req.Email)
	verified, err := h.redis.Get(ctx, verifiedKey).Result()
	if err != nil || verified != "1" {
		// Also allow direct code verification for single-step flow
		codeKey := fmt.Sprintf("reset_code:%s", req.Email)
		storedCode, err := h.redis.Get(ctx, codeKey).Result()
		if err != nil || storedCode != req.Code {
			return httputil.BadRequest(c, "invalid or expired verification, please start over")
		}
	}

	// Get user
	var userID uuid.UUID
	err = h.db.QueryRow(ctx,
		"SELECT id FROM users WHERE email = $1 AND deleted_at IS NULL",
		req.Email,
	).Scan(&userID)
	if err != nil {
		return httputil.BadRequest(c, "invalid request")
	}

	// Hash new password
	hashedPassword, err := hashPassword(req.NewPassword)
	if err != nil {
		return httputil.InternalError(c, "failed to process password")
	}

	// Update password
	_, err = h.db.Exec(ctx,
		"UPDATE users SET password_hash = $1, updated_at = NOW() WHERE id = $2",
		hashedPassword, userID,
	)
	if err != nil {
		return httputil.InternalError(c, "failed to update password")
	}

	// Cleanup Redis keys
	h.redis.Del(ctx, fmt.Sprintf("reset_code:%s", req.Email))
	h.redis.Del(ctx, fmt.Sprintf("reset_verified:%s", req.Email))
	h.redis.Del(ctx, fmt.Sprintf("reset_attempts:%s", req.Email))

	// Revoke all existing refresh tokens (security)
	_, _ = h.db.Exec(ctx,
		"UPDATE refresh_tokens SET revoked_at = NOW() WHERE user_id = $1 AND revoked_at IS NULL",
		userID,
	)

	return httputil.Success(c, map[string]string{
		"message": "Password has been reset successfully. Please log in with your new password.",
	})
}

// hashPassword hashes a password using bcrypt
func hashPassword(password string) (string, error) {
	hashed, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		return "", err
	}
	return string(hashed), nil
}
