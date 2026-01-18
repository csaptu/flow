package repository

import (
	"context"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

// User represents a user record from the shared database.
type User struct {
	ID              uuid.UUID
	Email           string
	Name            *string
	PasswordHash    *string
	Provider        *string
	ProviderID      *string
	EmailVerifiedAt *time.Time
	LastLoginAt     *time.Time
	CreatedAt       time.Time
	UpdatedAt       time.Time
}

// GetUserByID returns a user by ID.
func GetUserByID(ctx context.Context, userID uuid.UUID) (*User, error) {
	db := getPool()

	var u User
	err := db.QueryRow(ctx, `
		SELECT id, email, name, password_hash, provider, provider_id,
		       email_verified_at, last_login_at, created_at, updated_at
		FROM users
		WHERE id = $1
	`, userID).Scan(
		&u.ID, &u.Email, &u.Name, &u.PasswordHash, &u.Provider, &u.ProviderID,
		&u.EmailVerifiedAt, &u.LastLoginAt, &u.CreatedAt, &u.UpdatedAt,
	)

	if err == pgx.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}

	return &u, nil
}

// GetUserByEmail returns a user by email.
func GetUserByEmail(ctx context.Context, email string) (*User, error) {
	db := getPool()

	var u User
	err := db.QueryRow(ctx, `
		SELECT id, email, name, password_hash, provider, provider_id,
		       email_verified_at, last_login_at, created_at, updated_at
		FROM users
		WHERE email = $1
	`, email).Scan(
		&u.ID, &u.Email, &u.Name, &u.PasswordHash, &u.Provider, &u.ProviderID,
		&u.EmailVerifiedAt, &u.LastLoginAt, &u.CreatedAt, &u.UpdatedAt,
	)

	if err == pgx.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}

	return &u, nil
}

// UserWithSubscription represents a user with subscription info for admin views.
type UserWithSubscription struct {
	UserID       uuid.UUID
	Email        string
	Name         *string
	Tier         string
	Status       string
	PeriodStart  *time.Time
	PeriodEnd    *time.Time
	CancelledAt  *time.Time
	UserCreatedAt time.Time
}

// ListUsersWithSubscriptions returns users with their subscription info (admin use).
func ListUsersWithSubscriptions(ctx context.Context, tier string, limit, offset int) ([]UserWithSubscription, int, error) {
	db := getPool()

	// Build query
	countQuery := `
		SELECT COUNT(*)
		FROM users u
		LEFT JOIN subscriptions s ON u.id = s.user_id
		WHERE 1=1
	`
	listQuery := `
		SELECT u.id, u.email, u.name,
		       COALESCE(s.tier, 'free') as tier,
		       COALESCE(s.status, 'active') as status,
		       s.current_period_start, s.current_period_end, s.cancelled_at,
		       u.created_at
		FROM users u
		LEFT JOIN subscriptions s ON u.id = s.user_id
		WHERE 1=1
	`

	var total int
	var rows pgx.Rows
	var err error

	if tier != "" {
		countQuery += " AND COALESCE(s.tier, 'free') = $1"
		listQuery += " AND COALESCE(s.tier, 'free') = $1 ORDER BY u.created_at DESC LIMIT $2 OFFSET $3"
		err = db.QueryRow(ctx, countQuery, tier).Scan(&total)
		if err != nil {
			return nil, 0, err
		}
		rows, err = db.Query(ctx, listQuery, tier, limit, offset)
	} else {
		err = db.QueryRow(ctx, countQuery).Scan(&total)
		if err != nil {
			return nil, 0, err
		}
		listQuery += " ORDER BY u.created_at DESC LIMIT $1 OFFSET $2"
		rows, err = db.Query(ctx, listQuery, limit, offset)
	}
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	var users []UserWithSubscription
	for rows.Next() {
		var u UserWithSubscription
		err := rows.Scan(
			&u.UserID, &u.Email, &u.Name, &u.Tier, &u.Status,
			&u.PeriodStart, &u.PeriodEnd, &u.CancelledAt, &u.UserCreatedAt,
		)
		if err != nil {
			continue
		}
		users = append(users, u)
	}

	return users, total, nil
}
