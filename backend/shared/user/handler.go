package user

import (
	"time"

	"github.com/gofiber/fiber/v2"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/csaptu/flow/common/dto"
	"github.com/csaptu/flow/common/errors"
	"github.com/csaptu/flow/common/models"
	"github.com/csaptu/flow/pkg/httputil"
	"github.com/csaptu/flow/pkg/middleware"
)

// Handler handles user endpoints
type Handler struct {
	db *pgxpool.Pool
}

// NewHandler creates a new user handler
func NewHandler(db *pgxpool.Pool) *Handler {
	return &Handler{db: db}
}

// UpdateRequest represents the user update request body
type UpdateRequest struct {
	Name      *string `json:"name,omitempty"`
	AvatarURL *string `json:"avatar_url,omitempty"`
	Settings  *string `json:"settings,omitempty"`
}

// GetByID handles getting a user by ID
func (h *Handler) GetByID(c *fiber.Ctx) error {
	// Get user ID from URL
	idParam := c.Params("id")
	id, err := uuid.Parse(idParam)
	if err != nil {
		return httputil.BadRequest(c, "invalid user ID")
	}

	// Check authorization (users can only view themselves)
	authUserID, err := middleware.GetUserID(c)
	if err != nil {
		return httputil.Error(c, err)
	}
	if authUserID != id {
		return httputil.Forbidden(c, "you can only view your own profile")
	}

	// Get user from database
	var user models.User
	err = h.db.QueryRow(c.Context(),
		`SELECT id, email, email_verified, name, avatar_url, settings, created_at, updated_at
		 FROM users WHERE id = $1 AND deleted_at IS NULL`,
		id,
	).Scan(&user.ID, &user.Email, &user.EmailVerified, &user.Name, &user.AvatarURL,
		&user.Settings, &user.CreatedAt, &user.UpdatedAt)

	if err == pgx.ErrNoRows {
		return httputil.Error(c, errors.NotFound("user"))
	}
	if err != nil {
		return httputil.InternalError(c, "database error")
	}

	return httputil.Success(c, toUserResponse(&user))
}

// Update handles updating a user
func (h *Handler) Update(c *fiber.Ctx) error {
	// Get user ID from URL
	idParam := c.Params("id")
	id, err := uuid.Parse(idParam)
	if err != nil {
		return httputil.BadRequest(c, "invalid user ID")
	}

	// Check authorization
	authUserID, err := middleware.GetUserID(c)
	if err != nil {
		return httputil.Error(c, err)
	}
	if authUserID != id {
		return httputil.Forbidden(c, "you can only update your own profile")
	}

	// Parse request body
	var req UpdateRequest
	if err := c.BodyParser(&req); err != nil {
		return httputil.BadRequest(c, "invalid request body")
	}

	// Build update query dynamically
	updates := make(map[string]interface{})
	if req.Name != nil {
		updates["name"] = *req.Name
	}
	if req.AvatarURL != nil {
		updates["avatar_url"] = *req.AvatarURL
	}
	if req.Settings != nil {
		updates["settings"] = *req.Settings
	}

	if len(updates) == 0 {
		return httputil.BadRequest(c, "no fields to update")
	}

	updates["updated_at"] = time.Now()

	// Execute update
	query := "UPDATE users SET "
	args := make([]interface{}, 0)
	i := 1
	for k, v := range updates {
		if i > 1 {
			query += ", "
		}
		query += k + " = $" + string(rune('0'+i))
		args = append(args, v)
		i++
	}
	query += " WHERE id = $" + string(rune('0'+i)) + " AND deleted_at IS NULL"
	args = append(args, id)

	result, err := h.db.Exec(c.Context(), query, args...)
	if err != nil {
		return httputil.InternalError(c, "failed to update user")
	}

	if result.RowsAffected() == 0 {
		return httputil.Error(c, errors.NotFound("user"))
	}

	// Get updated user
	var user models.User
	err = h.db.QueryRow(c.Context(),
		`SELECT id, email, email_verified, name, avatar_url, settings, created_at, updated_at
		 FROM users WHERE id = $1`,
		id,
	).Scan(&user.ID, &user.Email, &user.EmailVerified, &user.Name, &user.AvatarURL,
		&user.Settings, &user.CreatedAt, &user.UpdatedAt)
	if err != nil {
		return httputil.InternalError(c, "failed to fetch updated user")
	}

	return httputil.Success(c, toUserResponse(&user))
}

// Delete handles soft-deleting a user
func (h *Handler) Delete(c *fiber.Ctx) error {
	// Get user ID from URL
	idParam := c.Params("id")
	id, err := uuid.Parse(idParam)
	if err != nil {
		return httputil.BadRequest(c, "invalid user ID")
	}

	// Check authorization
	authUserID, err := middleware.GetUserID(c)
	if err != nil {
		return httputil.Error(c, err)
	}
	if authUserID != id {
		return httputil.Forbidden(c, "you can only delete your own account")
	}

	// Soft delete user
	result, err := h.db.Exec(c.Context(),
		"UPDATE users SET deleted_at = $1 WHERE id = $2 AND deleted_at IS NULL",
		time.Now(), id,
	)
	if err != nil {
		return httputil.InternalError(c, "failed to delete user")
	}

	if result.RowsAffected() == 0 {
		return httputil.Error(c, errors.NotFound("user"))
	}

	// Also revoke all refresh tokens for this user
	_, _ = h.db.Exec(c.Context(),
		"UPDATE refresh_tokens SET revoked_at = $1 WHERE user_id = $2 AND revoked_at IS NULL",
		time.Now(), id,
	)

	return httputil.NoContent(c)
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
