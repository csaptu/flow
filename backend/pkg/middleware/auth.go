package middleware

import (
	"strings"
	"time"

	"github.com/gofiber/fiber/v2"
	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
	"github.com/tupham/flow/common/errors"
	"github.com/tupham/flow/pkg/httputil"
)

// TokenClaims represents the JWT claims structure
type TokenClaims struct {
	jwt.RegisteredClaims
	UserID    uuid.UUID `json:"uid"`
	Email     string    `json:"email"`
	TokenType string    `json:"type"` // "access" or "refresh"
}

// AuthConfig holds configuration for the auth middleware
type AuthConfig struct {
	JWTSecret     string
	SkipPaths     []string
	PublicPaths   []string // Paths that allow optional auth
}

// Auth creates a JWT authentication middleware
func Auth(config AuthConfig) fiber.Handler {
	return func(c *fiber.Ctx) error {
		path := c.Path()

		// Check if path should be skipped
		for _, skipPath := range config.SkipPaths {
			if strings.HasPrefix(path, skipPath) {
				return c.Next()
			}
		}

		// Check if path allows optional auth
		isPublic := false
		for _, publicPath := range config.PublicPaths {
			if strings.HasPrefix(path, publicPath) {
				isPublic = true
				break
			}
		}

		// Get token from Authorization header
		authHeader := c.Get("Authorization")
		if authHeader == "" {
			if isPublic {
				return c.Next()
			}
			return httputil.Unauthorized(c, "missing authorization header")
		}

		// Extract token from "Bearer <token>"
		parts := strings.Split(authHeader, " ")
		if len(parts) != 2 || strings.ToLower(parts[0]) != "bearer" {
			return httputil.Unauthorized(c, "invalid authorization header format")
		}

		tokenString := parts[1]

		// Parse and validate token
		claims, err := validateToken(tokenString, config.JWTSecret)
		if err != nil {
			if isPublic {
				return c.Next()
			}
			return httputil.Error(c, err)
		}

		// Verify it's an access token
		if claims.TokenType != "access" {
			return httputil.Unauthorized(c, "invalid token type")
		}

		// Store user info in context
		c.Locals("userID", claims.UserID)
		c.Locals("email", claims.Email)
		c.Locals("claims", claims)

		return c.Next()
	}
}

// validateToken parses and validates a JWT token
func validateToken(tokenString, secret string) (*TokenClaims, error) {
	token, err := jwt.ParseWithClaims(tokenString, &TokenClaims{}, func(token *jwt.Token) (interface{}, error) {
		// Verify signing method
		if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, errors.ErrInvalidToken
		}
		return []byte(secret), nil
	})

	if err != nil {
		if err == jwt.ErrTokenExpired {
			return nil, errors.ErrTokenExpired
		}
		return nil, errors.ErrInvalidToken
	}

	claims, ok := token.Claims.(*TokenClaims)
	if !ok || !token.Valid {
		return nil, errors.ErrInvalidToken
	}

	return claims, nil
}

// GenerateAccessToken generates a new access token
func GenerateAccessToken(userID uuid.UUID, email, secret string, expiry time.Duration) (string, time.Time, error) {
	expiresAt := time.Now().Add(expiry)

	claims := &TokenClaims{
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(expiresAt),
			IssuedAt:  jwt.NewNumericDate(time.Now()),
			NotBefore: jwt.NewNumericDate(time.Now()),
			Issuer:    "flow",
			Subject:   userID.String(),
		},
		UserID:    userID,
		Email:     email,
		TokenType: "access",
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	tokenString, err := token.SignedString([]byte(secret))
	if err != nil {
		return "", time.Time{}, err
	}

	return tokenString, expiresAt, nil
}

// GenerateRefreshToken generates a new refresh token
func GenerateRefreshToken(userID uuid.UUID, email, secret string, expiry time.Duration) (string, time.Time, error) {
	expiresAt := time.Now().Add(expiry)

	claims := &TokenClaims{
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(expiresAt),
			IssuedAt:  jwt.NewNumericDate(time.Now()),
			NotBefore: jwt.NewNumericDate(time.Now()),
			Issuer:    "flow",
			Subject:   userID.String(),
		},
		UserID:    userID,
		Email:     email,
		TokenType: "refresh",
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	tokenString, err := token.SignedString([]byte(secret))
	if err != nil {
		return "", time.Time{}, err
	}

	return tokenString, expiresAt, nil
}

// GetUserID extracts the user ID from the Fiber context
func GetUserID(c *fiber.Ctx) (uuid.UUID, error) {
	userID, ok := c.Locals("userID").(uuid.UUID)
	if !ok {
		return uuid.Nil, errors.ErrUnauthorized
	}
	return userID, nil
}

// GetEmail extracts the email from the Fiber context
func GetEmail(c *fiber.Ctx) string {
	email, _ := c.Locals("email").(string)
	return email
}

// GetClaims extracts the full claims from the Fiber context
func GetClaims(c *fiber.Ctx) *TokenClaims {
	claims, _ := c.Locals("claims").(*TokenClaims)
	return claims
}

// RequireUser is a helper that returns 401 if user is not authenticated
func RequireUser(c *fiber.Ctx) (uuid.UUID, error) {
	userID, err := GetUserID(c)
	if err != nil {
		return uuid.Nil, err
	}
	if userID == uuid.Nil {
		return uuid.Nil, errors.ErrUnauthorized
	}
	return userID, nil
}
