package subscription

import (
	"github.com/gofiber/fiber/v2"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/csaptu/flow/pkg/httputil"
	"github.com/csaptu/flow/shared/repository"
)

// Handler handles subscription-related HTTP endpoints.
// For internal monorepo calls, use shared/repository directly.
type Handler struct {
	db *pgxpool.Pool
}

// NewHandler creates a new subscription handler
func NewHandler(db *pgxpool.Pool) *Handler {
	return &Handler{db: db}
}

// GetUserSubscription returns subscription for a specific user
// GET /subscriptions/:user_id
func (h *Handler) GetUserSubscription(c *fiber.Ctx) error {
	userIDStr := c.Params("user_id")
	userID, err := uuid.Parse(userIDStr)
	if err != nil {
		return httputil.BadRequest(c, "invalid user_id")
	}

	sub, err := repository.GetUserSubscription(c.Context(), userID)
	if err != nil {
		return httputil.InternalError(c, "failed to get subscription")
	}

	return httputil.Success(c, sub)
}

// ListPlans returns all active subscription plans
// GET /plans
func (h *Handler) ListPlans(c *fiber.Ctx) error {
	plans, err := repository.ListPlans(c.Context())
	if err != nil {
		return httputil.InternalError(c, "failed to list plans")
	}

	return httputil.Success(c, map[string]interface{}{
		"items": plans,
		"total": len(plans),
	})
}

// GetPlan returns a specific subscription plan
// GET /plans/:plan_id
func (h *Handler) GetPlan(c *fiber.Ctx) error {
	planID := c.Params("plan_id")

	plan, err := repository.GetPlan(c.Context(), planID)
	if err != nil {
		return httputil.InternalError(c, "failed to get plan")
	}
	if plan == nil {
		return httputil.NotFound(c, "plan not found")
	}

	return httputil.Success(c, plan)
}

// CheckAdmin checks if a user email is an admin
// GET /internal/admin/check/:email
func (h *Handler) CheckAdmin(c *fiber.Ctx) error {
	email := c.Params("email")
	if email == "" {
		return httputil.BadRequest(c, "email is required")
	}

	isAdmin, err := repository.IsAdmin(c.Context(), email)
	if err != nil {
		return httputil.InternalError(c, "failed to check admin status")
	}

	role := ""
	if isAdmin {
		role, _ = repository.GetAdminRole(c.Context(), email)
	}

	return httputil.Success(c, map[string]interface{}{
		"is_admin": isAdmin,
		"role":     role,
	})
}
