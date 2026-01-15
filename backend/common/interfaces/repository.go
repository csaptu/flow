package interfaces

import (
	"context"

	"github.com/google/uuid"
	"github.com/csaptu/flow/common/models"
)

// UserRepository defines the interface for user data operations
type UserRepository interface {
	// Create creates a new user
	Create(ctx context.Context, user *models.User) error
	// GetByID retrieves a user by ID
	GetByID(ctx context.Context, id uuid.UUID) (*models.User, error)
	// GetByEmail retrieves a user by email
	GetByEmail(ctx context.Context, email string) (*models.User, error)
	// GetByGoogleID retrieves a user by Google OAuth ID
	GetByGoogleID(ctx context.Context, googleID string) (*models.User, error)
	// GetByAppleID retrieves a user by Apple OAuth ID
	GetByAppleID(ctx context.Context, appleID string) (*models.User, error)
	// GetByMicrosoftID retrieves a user by Microsoft OAuth ID
	GetByMicrosoftID(ctx context.Context, microsoftID string) (*models.User, error)
	// Update updates a user's information
	Update(ctx context.Context, user *models.User) error
	// UpdateLastLogin updates the last login timestamp
	UpdateLastLogin(ctx context.Context, id uuid.UUID) error
	// Delete soft-deletes a user
	Delete(ctx context.Context, id uuid.UUID) error
}

// RefreshToken represents a refresh token for JWT rotation
type RefreshToken struct {
	ID         uuid.UUID
	UserID     uuid.UUID
	TokenHash  string
	DeviceInfo map[string]interface{}
	ExpiresAt  interface{}
	CreatedAt  interface{}
	RevokedAt  *interface{}
}

// RefreshTokenRepository defines the interface for refresh token operations
type RefreshTokenRepository interface {
	// Create stores a new refresh token
	Create(ctx context.Context, token *RefreshToken) error
	// GetByHash retrieves a refresh token by its hash
	GetByHash(ctx context.Context, hash string) (*RefreshToken, error)
	// Revoke marks a refresh token as revoked
	Revoke(ctx context.Context, id uuid.UUID) error
	// RevokeAllForUser revokes all refresh tokens for a user
	RevokeAllForUser(ctx context.Context, userID uuid.UUID) error
	// DeleteExpired removes expired refresh tokens
	DeleteExpired(ctx context.Context) error
}

// TaskBaseLike is an interface for entities that embed TaskBase
type TaskBaseLike interface {
	GetID() uuid.UUID
	GetUserID() uuid.UUID
	GetStatus() models.Status
	GetPriority() models.Priority
	IsCompleted() bool
	IsOverdue() bool
}
