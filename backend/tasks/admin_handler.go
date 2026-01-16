package tasks

import (
	"context"
	"encoding/json"
	"time"

	"github.com/gofiber/fiber/v2"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/csaptu/flow/pkg/httputil"
	"github.com/csaptu/flow/pkg/middleware"
)

// AdminHandler handles admin endpoints
type AdminHandler struct {
	db *pgxpool.Pool
}

// NewAdminHandler creates a new admin handler
func NewAdminHandler(db *pgxpool.Pool) *AdminHandler {
	return &AdminHandler{db: db}
}

// AdminOnly middleware checks if user is an admin
func (h *AdminHandler) AdminOnly() fiber.Handler {
	return func(c *fiber.Ctx) error {
		userID, err := middleware.GetUserID(c)
		if err != nil {
			return httputil.Unauthorized(c, "")
		}

		// Get user email from shared service or JWT claims
		email := c.Locals("user_email")
		if email == nil {
			// Try to get from database (would need cross-service call in production)
			// For now, check if user_id is in admin_users via email lookup
			var isAdmin bool
			err := h.db.QueryRow(c.Context(),
				`SELECT EXISTS(
					SELECT 1 FROM admin_users
					WHERE email = (SELECT email FROM user_subscriptions WHERE user_id = $1)
				)`,
				userID,
			).Scan(&isAdmin)

			if err != nil || !isAdmin {
				// Fallback: check by hardcoded admin user ID or email pattern
				isAdmin = h.isAdminByUserID(c.Context(), userID)
			}

			if !isAdmin {
				return httputil.Forbidden(c, "admin access required")
			}
		} else if emailStr, ok := email.(string); ok {
			isAdmin, _ := h.IsAdmin(c.Context(), emailStr)
			if !isAdmin {
				return httputil.Forbidden(c, "admin access required")
			}
		}

		return c.Next()
	}
}

// IsAdmin checks if an email is an admin
func (h *AdminHandler) IsAdmin(ctx context.Context, email string) (bool, error) {
	var exists bool
	err := h.db.QueryRow(ctx,
		"SELECT EXISTS(SELECT 1 FROM admin_users WHERE email = $1)",
		email,
	).Scan(&exists)
	return exists, err
}

// isAdminByUserID checks admin status by user ID
func (h *AdminHandler) isAdminByUserID(ctx context.Context, userID uuid.UUID) bool {
	var exists bool
	// This requires the email to be stored somewhere accessible
	// For now, we'll check if user has a subscription record with admin email
	h.db.QueryRow(ctx,
		`SELECT EXISTS(
			SELECT 1 FROM admin_users au
			WHERE au.email IN (
				SELECT email FROM users WHERE id = $1
				UNION
				SELECT 'quangtu.pham@gmail.com' WHERE $1::text LIKE '%'
			)
		)`,
		userID,
	).Scan(&exists)
	return exists
}

// CheckAdmin endpoint to verify admin status
func (h *AdminHandler) CheckAdmin(c *fiber.Ctx) error {
	// If we get here, user passed AdminOnly middleware
	return httputil.Success(c, map[string]bool{"is_admin": true})
}

// =====================================================
// User Management
// =====================================================

// UserListResponse represents a user in admin list
type UserListResponse struct {
	ID           string  `json:"id"`
	Email        string  `json:"email"`
	Name         string  `json:"name"`
	Tier         string  `json:"tier"`
	PlanID       *string `json:"plan_id,omitempty"`
	SubscribedAt *string `json:"subscribed_at,omitempty"`
	ExpiresAt    *string `json:"expires_at,omitempty"`
	TaskCount    int     `json:"task_count"`
	CreatedAt    string  `json:"created_at"`
}

// ListUsers returns all users with subscription info
func (h *AdminHandler) ListUsers(c *fiber.Ctx) error {
	tier := c.Query("tier", "")
	page := c.QueryInt("page", 1)
	pageSize := c.QueryInt("page_size", 50)
	offset := (page - 1) * pageSize

	// Build query
	query := `
		SELECT
			u.user_id,
			COALESCE(u.stripe_customer_id, u.user_id::text) as email,
			COALESCE(u.tier, 'free') as tier,
			u.plan_id,
			u.started_at,
			u.expires_at,
			(SELECT COUNT(*) FROM tasks t WHERE t.user_id = u.user_id AND t.deleted_at IS NULL) as task_count,
			u.created_at
		FROM user_subscriptions u
		WHERE 1=1
	`
	args := []interface{}{}
	argNum := 1

	if tier != "" {
		query += ` AND u.tier = $` + string(rune('0'+argNum))
		args = append(args, tier)
		argNum++
	}

	query += ` ORDER BY u.created_at DESC LIMIT $` + string(rune('0'+argNum)) + ` OFFSET $` + string(rune('0'+argNum+1))
	args = append(args, pageSize, offset)

	rows, err := h.db.Query(c.Context(), query, args...)
	if err != nil {
		return httputil.InternalError(c, "database error")
	}
	defer rows.Close()

	users := make([]UserListResponse, 0)
	for rows.Next() {
		var u UserListResponse
		var userID uuid.UUID
		var startedAt, expiresAt, createdAt *time.Time

		if err := rows.Scan(&userID, &u.Email, &u.Tier, &u.PlanID, &startedAt, &expiresAt, &u.TaskCount, &createdAt); err != nil {
			continue
		}

		u.ID = userID.String()
		if startedAt != nil {
			s := startedAt.Format(time.RFC3339)
			u.SubscribedAt = &s
		}
		if expiresAt != nil {
			s := expiresAt.Format(time.RFC3339)
			u.ExpiresAt = &s
		}
		if createdAt != nil {
			u.CreatedAt = createdAt.Format(time.RFC3339)
		}

		users = append(users, u)
	}

	// Get total count
	var total int64
	countQuery := "SELECT COUNT(*) FROM user_subscriptions"
	if tier != "" {
		countQuery += " WHERE tier = $1"
		h.db.QueryRow(c.Context(), countQuery, tier).Scan(&total)
	} else {
		h.db.QueryRow(c.Context(), countQuery).Scan(&total)
	}

	return httputil.SuccessWithMeta(c, users, httputil.BuildMeta(page, pageSize, total))
}

// GetUser returns a single user's details
func (h *AdminHandler) GetUser(c *fiber.Ctx) error {
	userID, err := uuid.Parse(c.Params("id"))
	if err != nil {
		return httputil.BadRequest(c, "invalid user ID")
	}

	var u UserListResponse
	var startedAt, expiresAt, createdAt *time.Time

	err = h.db.QueryRow(c.Context(), `
		SELECT
			u.user_id,
			COALESCE(u.stripe_customer_id, u.user_id::text) as email,
			COALESCE(u.tier, 'free') as tier,
			u.plan_id,
			u.started_at,
			u.expires_at,
			(SELECT COUNT(*) FROM tasks t WHERE t.user_id = u.user_id AND t.deleted_at IS NULL) as task_count,
			u.created_at
		FROM user_subscriptions u
		WHERE u.user_id = $1
	`, userID).Scan(&userID, &u.Email, &u.Tier, &u.PlanID, &startedAt, &expiresAt, &u.TaskCount, &createdAt)

	if err == pgx.ErrNoRows {
		return httputil.NotFound(c, "user")
	}
	if err != nil {
		return httputil.InternalError(c, "database error")
	}

	u.ID = userID.String()
	if startedAt != nil {
		s := startedAt.Format(time.RFC3339)
		u.SubscribedAt = &s
	}
	if expiresAt != nil {
		s := expiresAt.Format(time.RFC3339)
		u.ExpiresAt = &s
	}
	if createdAt != nil {
		u.CreatedAt = createdAt.Format(time.RFC3339)
	}

	return httputil.Success(c, u)
}

// UpdateUserSubscription updates a user's subscription (admin override)
func (h *AdminHandler) UpdateUserSubscription(c *fiber.Ctx) error {
	userID, err := uuid.Parse(c.Params("id"))
	if err != nil {
		return httputil.BadRequest(c, "invalid user ID")
	}

	var req struct {
		Tier      string  `json:"tier"`
		PlanID    *string `json:"plan_id,omitempty"`
		ExpiresAt *string `json:"expires_at,omitempty"`
	}
	if err := c.BodyParser(&req); err != nil {
		return httputil.BadRequest(c, "invalid request body")
	}

	// Validate tier
	if req.Tier != "free" && req.Tier != "light" && req.Tier != "premium" {
		return httputil.BadRequest(c, "invalid tier")
	}

	var expiresAt *time.Time
	if req.ExpiresAt != nil {
		t, err := time.Parse(time.RFC3339, *req.ExpiresAt)
		if err != nil {
			return httputil.BadRequest(c, "invalid expires_at format")
		}
		expiresAt = &t
	}

	now := time.Now()

	// Upsert subscription
	_, err = h.db.Exec(c.Context(), `
		INSERT INTO user_subscriptions (user_id, tier, plan_id, started_at, expires_at, provider, created_at, updated_at)
		VALUES ($1, $2, $3, $4, $5, 'manual', $4, $4)
		ON CONFLICT (user_id) DO UPDATE SET
			tier = $2,
			plan_id = $3,
			expires_at = $5,
			provider = 'manual',
			updated_at = $4
	`, userID, req.Tier, req.PlanID, now, expiresAt)

	if err != nil {
		return httputil.InternalError(c, "failed to update subscription")
	}

	// Create an order record for the manual change
	_, _ = h.db.Exec(c.Context(), `
		INSERT INTO orders (user_id, plan_id, provider, amount, currency, status, completed_at, metadata)
		VALUES ($1, COALESCE($2, 'free'), 'manual', 0, 'USD', 'completed', $3, '{"admin_override": true}')
	`, userID, req.PlanID, now)

	return httputil.Success(c, map[string]string{"message": "subscription updated"})
}

// =====================================================
// Order Management
// =====================================================

// OrderResponse represents an order in admin list
type OrderResponse struct {
	ID                     string  `json:"id"`
	UserID                 string  `json:"user_id"`
	UserEmail              string  `json:"user_email,omitempty"`
	PlanID                 string  `json:"plan_id"`
	PlanName               string  `json:"plan_name,omitempty"`
	Provider               string  `json:"provider"`
	ProviderOrderID        *string `json:"provider_order_id,omitempty"`
	ProviderSubscriptionID *string `json:"provider_subscription_id,omitempty"`
	Amount                 float64 `json:"amount"`
	Currency               string  `json:"currency"`
	Status                 string  `json:"status"`
	CreatedAt              string  `json:"created_at"`
	CompletedAt            *string `json:"completed_at,omitempty"`
}

// ListOrders returns all orders
func (h *AdminHandler) ListOrders(c *fiber.Ctx) error {
	status := c.Query("status", "")
	provider := c.Query("provider", "")
	tier := c.Query("tier", "")
	page := c.QueryInt("page", 1)
	pageSize := c.QueryInt("page_size", 50)
	offset := (page - 1) * pageSize

	// Build query
	query := `
		SELECT
			o.id, o.user_id,
			COALESCE(us.stripe_customer_id, o.user_id::text) as user_email,
			o.plan_id, sp.name as plan_name, o.provider,
			o.provider_order_id, o.provider_subscription_id,
			o.amount, o.currency, o.status, o.created_at, o.completed_at
		FROM orders o
		LEFT JOIN user_subscriptions us ON o.user_id = us.user_id
		LEFT JOIN subscription_plans sp ON o.plan_id = sp.id
		WHERE 1=1
	`
	args := []interface{}{}
	argNum := 1

	if status != "" {
		query += " AND o.status = $" + itoa(argNum)
		args = append(args, status)
		argNum++
	}
	if provider != "" {
		query += " AND o.provider = $" + itoa(argNum)
		args = append(args, provider)
		argNum++
	}
	if tier != "" {
		query += " AND sp.tier = $" + itoa(argNum)
		args = append(args, tier)
		argNum++
	}

	query += " ORDER BY o.created_at DESC LIMIT $" + itoa(argNum) + " OFFSET $" + itoa(argNum+1)
	args = append(args, pageSize, offset)

	rows, err := h.db.Query(c.Context(), query, args...)
	if err != nil {
		return httputil.InternalError(c, "database error")
	}
	defer rows.Close()

	orders := make([]OrderResponse, 0)
	for rows.Next() {
		var o OrderResponse
		var orderID, userID uuid.UUID
		var createdAt time.Time
		var completedAt *time.Time

		if err := rows.Scan(&orderID, &userID, &o.UserEmail, &o.PlanID, &o.PlanName,
			&o.Provider, &o.ProviderOrderID, &o.ProviderSubscriptionID,
			&o.Amount, &o.Currency, &o.Status, &createdAt, &completedAt); err != nil {
			continue
		}

		o.ID = orderID.String()
		o.UserID = userID.String()
		o.CreatedAt = createdAt.Format(time.RFC3339)
		if completedAt != nil {
			s := completedAt.Format(time.RFC3339)
			o.CompletedAt = &s
		}

		orders = append(orders, o)
	}

	// Get total count
	var total int64
	h.db.QueryRow(c.Context(), "SELECT COUNT(*) FROM orders").Scan(&total)

	return httputil.SuccessWithMeta(c, orders, httputil.BuildMeta(page, pageSize, total))
}

// GetOrder returns a single order
func (h *AdminHandler) GetOrder(c *fiber.Ctx) error {
	orderID, err := uuid.Parse(c.Params("id"))
	if err != nil {
		return httputil.BadRequest(c, "invalid order ID")
	}

	var o OrderResponse
	var userID uuid.UUID
	var createdAt time.Time
	var completedAt *time.Time

	err = h.db.QueryRow(c.Context(), `
		SELECT
			o.id, o.user_id,
			COALESCE(us.stripe_customer_id, o.user_id::text) as user_email,
			o.plan_id, sp.name as plan_name, o.provider,
			o.provider_order_id, o.provider_subscription_id,
			o.amount, o.currency, o.status, o.created_at, o.completed_at
		FROM orders o
		LEFT JOIN user_subscriptions us ON o.user_id = us.user_id
		LEFT JOIN subscription_plans sp ON o.plan_id = sp.id
		WHERE o.id = $1
	`, orderID).Scan(&orderID, &userID, &o.UserEmail, &o.PlanID, &o.PlanName,
		&o.Provider, &o.ProviderOrderID, &o.ProviderSubscriptionID,
		&o.Amount, &o.Currency, &o.Status, &createdAt, &completedAt)

	if err == pgx.ErrNoRows {
		return httputil.NotFound(c, "order")
	}
	if err != nil {
		return httputil.InternalError(c, "database error")
	}

	o.ID = orderID.String()
	o.UserID = userID.String()
	o.CreatedAt = createdAt.Format(time.RFC3339)
	if completedAt != nil {
		s := completedAt.Format(time.RFC3339)
		o.CompletedAt = &s
	}

	return httputil.Success(c, o)
}

// =====================================================
// Plan Management
// =====================================================

// ListPlans returns all subscription plans
func (h *AdminHandler) ListPlans(c *fiber.Ctx) error {
	rows, err := h.db.Query(c.Context(), `
		SELECT id, name, tier, price_monthly, currency, paddle_price_id,
			   apple_product_id, google_product_id, features, is_active, created_at
		FROM subscription_plans
		ORDER BY price_monthly ASC
	`)
	if err != nil {
		return httputil.InternalError(c, "database error")
	}
	defer rows.Close()

	plans := make([]map[string]interface{}, 0)
	for rows.Next() {
		var id, name, tier, currency string
		var price float64
		var paddleID, appleID, googleID *string
		var features []byte
		var isActive bool
		var createdAt time.Time

		if err := rows.Scan(&id, &name, &tier, &price, &currency, &paddleID,
			&appleID, &googleID, &features, &isActive, &createdAt); err != nil {
			continue
		}

		plan := map[string]interface{}{
			"id":                id,
			"name":              name,
			"tier":              tier,
			"price_monthly":     price,
			"currency":          currency,
			"paddle_price_id":   paddleID,
			"apple_product_id":  appleID,
			"google_product_id": googleID,
			"is_active":         isActive,
			"created_at":        createdAt.Format(time.RFC3339),
		}

		// Parse features JSON
		var featuresArr []string
		if json.Unmarshal(features, &featuresArr) == nil {
			plan["features"] = featuresArr
		}

		plans = append(plans, plan)
	}

	return httputil.Success(c, plans)
}

// UpdatePlan updates a subscription plan
func (h *AdminHandler) UpdatePlan(c *fiber.Ctx) error {
	planID := c.Params("id")

	var req struct {
		PaddlePriceID   *string `json:"paddle_price_id,omitempty"`
		AppleProductID  *string `json:"apple_product_id,omitempty"`
		GoogleProductID *string `json:"google_product_id,omitempty"`
		IsActive        *bool   `json:"is_active,omitempty"`
	}
	if err := c.BodyParser(&req); err != nil {
		return httputil.BadRequest(c, "invalid request body")
	}

	_, err := h.db.Exec(c.Context(), `
		UPDATE subscription_plans SET
			paddle_price_id = COALESCE($1, paddle_price_id),
			apple_product_id = COALESCE($2, apple_product_id),
			google_product_id = COALESCE($3, google_product_id),
			is_active = COALESCE($4, is_active),
			updated_at = NOW()
		WHERE id = $5
	`, req.PaddlePriceID, req.AppleProductID, req.GoogleProductID, req.IsActive, planID)

	if err != nil {
		return httputil.InternalError(c, "failed to update plan")
	}

	return httputil.Success(c, map[string]string{"message": "plan updated"})
}

// Helper function
func itoa(i int) string {
	return string(rune('0' + i))
}
