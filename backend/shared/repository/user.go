package repository

import (
	"context"
	"encoding/json"
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

// AIPreferences represents user's AI feature preferences
// Each feature can be "auto" (automatic) or "ask" (manual)
type AIPreferences struct {
	CleanTitle       string `json:"clean_title"`
	CleanDescription string `json:"clean_description"`
	Decompose        string `json:"decompose"`
	EntityExtraction string `json:"entity_extraction"`
	DuplicateCheck   string `json:"duplicate_check"`
	Complexity       string `json:"complexity"`
	SmartDueDate     string `json:"smart_due_date"`
}

// DefaultAIPreferences returns the default AI preferences
func DefaultAIPreferences() AIPreferences {
	return AIPreferences{
		CleanTitle:       "auto",
		CleanDescription: "auto",
		Decompose:        "ask",
		EntityExtraction: "auto",
		DuplicateCheck:   "ask",
		Complexity:       "auto",
		SmartDueDate:     "auto",
	}
}

// GetUserAIPreferences retrieves AI preferences for a user
func GetUserAIPreferences(ctx context.Context, userID uuid.UUID) (*AIPreferences, error) {
	db := getPool()

	var prefsJSON []byte
	err := db.QueryRow(ctx, `
		SELECT COALESCE(ai_preferences, '{}')
		FROM users
		WHERE id = $1
	`, userID).Scan(&prefsJSON)

	if err == pgx.ErrNoRows {
		defaults := DefaultAIPreferences()
		return &defaults, nil
	}
	if err != nil {
		return nil, err
	}

	// Start with defaults and override with stored values
	prefs := DefaultAIPreferences()
	if len(prefsJSON) > 0 {
		if err := json.Unmarshal(prefsJSON, &prefs); err != nil {
			// Return defaults on parse error
			return &prefs, nil
		}
	}

	return &prefs, nil
}

// UpdateUserAIPreferences updates AI preferences for a user
func UpdateUserAIPreferences(ctx context.Context, userID uuid.UUID, prefs *AIPreferences) error {
	db := getPool()

	prefsJSON, err := json.Marshal(prefs)
	if err != nil {
		return err
	}

	_, err = db.Exec(ctx, `
		UPDATE users
		SET ai_preferences = $1, updated_at = NOW()
		WHERE id = $2
	`, prefsJSON, userID)

	return err
}

// GetUserAIPreferencesMap retrieves AI preferences as a map (for API responses)
func GetUserAIPreferencesMap(ctx context.Context, userID uuid.UUID) (map[string]string, error) {
	prefs, err := GetUserAIPreferences(ctx, userID)
	if err != nil {
		return nil, err
	}

	return map[string]string{
		"clean_title":       prefs.CleanTitle,
		"clean_description": prefs.CleanDescription,
		"decompose":         prefs.Decompose,
		"entity_extraction": prefs.EntityExtraction,
		"duplicate_check":   prefs.DuplicateCheck,
		"complexity":        prefs.Complexity,
		"smart_due_date":    prefs.SmartDueDate,
	}, nil
}
