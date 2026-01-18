package repository

import (
	"context"
	"time"

	"github.com/jackc/pgx/v5"
)

// AdminUser represents an admin user
type AdminUser struct {
	Email   string
	Role    string
	AddedAt time.Time
	AddedBy *string
}

// IsAdmin checks if an email is in the admin list.
func IsAdmin(ctx context.Context, email string) (bool, error) {
	db := getPool()

	var exists bool
	err := db.QueryRow(ctx, `
		SELECT EXISTS(SELECT 1 FROM admin_users WHERE email = $1)
	`, email).Scan(&exists)

	if err != nil {
		return false, err
	}

	return exists, nil
}

// GetAdminRole returns the admin role for an email.
// Returns empty string if not an admin.
func GetAdminRole(ctx context.Context, email string) (string, error) {
	db := getPool()

	var role string
	err := db.QueryRow(ctx, `
		SELECT role FROM admin_users WHERE email = $1
	`, email).Scan(&role)

	if err == pgx.ErrNoRows {
		return "", nil
	}
	if err != nil {
		return "", err
	}

	return role, nil
}

// ListAdmins returns all admin users.
func ListAdmins(ctx context.Context) ([]AdminUser, error) {
	db := getPool()

	rows, err := db.Query(ctx, `
		SELECT email, role, added_at, added_by
		FROM admin_users
		ORDER BY added_at DESC
	`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var admins []AdminUser
	for rows.Next() {
		var a AdminUser
		if err := rows.Scan(&a.Email, &a.Role, &a.AddedAt, &a.AddedBy); err != nil {
			continue
		}
		admins = append(admins, a)
	}

	return admins, nil
}

// AddAdmin adds a new admin user.
func AddAdmin(ctx context.Context, email, role, addedBy string) error {
	db := getPool()

	_, err := db.Exec(ctx, `
		INSERT INTO admin_users (email, role, added_at, added_by)
		VALUES ($1, $2, NOW(), $3)
		ON CONFLICT (email) DO UPDATE SET
			role = EXCLUDED.role,
			added_by = EXCLUDED.added_by
	`, email, role, addedBy)

	return err
}

// RemoveAdmin removes an admin user.
func RemoveAdmin(ctx context.Context, email string) error {
	db := getPool()

	_, err := db.Exec(ctx, `
		DELETE FROM admin_users WHERE email = $1
	`, email)

	return err
}
