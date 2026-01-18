package tasks

import (
	"time"

	"github.com/gofiber/fiber/v2"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/csaptu/flow/pkg/httputil"
	"github.com/csaptu/flow/pkg/middleware"
	"github.com/csaptu/flow/shared/repository"
)

// AdminHandler handles admin endpoints
type AdminHandler struct {
	db *pgxpool.Pool
}

// NewAdminHandler creates a new admin handler
func NewAdminHandler(db *pgxpool.Pool) *AdminHandler {
	return &AdminHandler{db: db}
}

// AdminOnly middleware checks if user is an admin using the shared repository
func (h *AdminHandler) AdminOnly() fiber.Handler {
	return func(c *fiber.Ctx) error {
		_, err := middleware.GetUserID(c)
		if err != nil {
			return httputil.Unauthorized(c, "")
		}

		// Get user email from JWT claims (stored by auth middleware)
		email := middleware.GetEmail(c)
		if email == "" {
			return httputil.Forbidden(c, "admin access required")
		}

		// Check if email is in admin_users table via shared repository
		isAdmin, err := repository.IsAdmin(c.Context(), email)
		if err != nil || !isAdmin {
			return httputil.Forbidden(c, "admin access required")
		}

		return c.Next()
	}
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

// ListUsers returns all users with subscription info (from shared repository)
func (h *AdminHandler) ListUsers(c *fiber.Ctx) error {
	tier := c.Query("tier", "")
	page := c.QueryInt("page", 1)
	pageSize := c.QueryInt("page_size", 50)
	offset := (page - 1) * pageSize

	// Get users with subscriptions from shared repository
	usersWithSubs, total, err := repository.ListUsersWithSubscriptions(c.Context(), tier, pageSize, offset)
	if err != nil {
		return httputil.InternalError(c, "failed to list users")
	}

	users := make([]UserListResponse, 0, len(usersWithSubs))
	for _, u := range usersWithSubs {
		// Get task count from local tasks table
		var taskCount int
		h.db.QueryRow(c.Context(),
			"SELECT COUNT(*) FROM tasks WHERE user_id = $1 AND deleted_at IS NULL",
			u.UserID,
		).Scan(&taskCount)

		response := UserListResponse{
			ID:        u.UserID.String(),
			Email:     u.Email,
			Tier:      u.Tier,
			TaskCount: taskCount,
			CreatedAt: u.UserCreatedAt.Format(time.RFC3339),
		}

		if u.Name != nil {
			response.Name = *u.Name
		}
		if u.PeriodStart != nil {
			s := u.PeriodStart.Format(time.RFC3339)
			response.SubscribedAt = &s
		}
		if u.PeriodEnd != nil {
			s := u.PeriodEnd.Format(time.RFC3339)
			response.ExpiresAt = &s
		}

		users = append(users, response)
	}

	return httputil.SuccessWithMeta(c, users, httputil.BuildMeta(page, pageSize, int64(total)))
}

// GetUser returns a single user's details (from shared repository)
func (h *AdminHandler) GetUser(c *fiber.Ctx) error {
	userID, err := uuid.Parse(c.Params("id"))
	if err != nil {
		return httputil.BadRequest(c, "invalid user ID")
	}

	// Get user from shared repository
	user, err := repository.GetUserByID(c.Context(), userID)
	if err != nil {
		return httputil.InternalError(c, "failed to get user")
	}
	if user == nil {
		return httputil.NotFound(c, "user")
	}

	// Get subscription from shared repository
	sub, err := repository.GetUserSubscription(c.Context(), userID)
	if err != nil {
		return httputil.InternalError(c, "failed to get subscription")
	}

	// Get task count from local tasks table
	var taskCount int
	h.db.QueryRow(c.Context(),
		"SELECT COUNT(*) FROM tasks WHERE user_id = $1 AND deleted_at IS NULL",
		userID,
	).Scan(&taskCount)

	response := UserListResponse{
		ID:        user.ID.String(),
		Email:     user.Email,
		Tier:      sub.Tier,
		TaskCount: taskCount,
		CreatedAt: user.CreatedAt.Format(time.RFC3339),
	}

	if user.Name != nil {
		response.Name = *user.Name
	}
	if sub.CurrentPeriodStart != nil {
		s := sub.CurrentPeriodStart.Format(time.RFC3339)
		response.SubscribedAt = &s
	}
	if sub.CurrentPeriodEnd != nil {
		s := sub.CurrentPeriodEnd.Format(time.RFC3339)
		response.ExpiresAt = &s
	}

	return httputil.Success(c, response)
}

// UpdateUserSubscription updates a user's subscription (admin override) via shared repository
func (h *AdminHandler) UpdateUserSubscription(c *fiber.Ctx) error {
	userID, err := uuid.Parse(c.Params("id"))
	if err != nil {
		return httputil.BadRequest(c, "invalid user ID")
	}

	var req struct {
		Tier      string  `json:"tier"`
		StartsAt  *string `json:"starts_at,omitempty"`
		ExpiresAt *string `json:"expires_at,omitempty"`
	}
	if err := c.BodyParser(&req); err != nil {
		return httputil.BadRequest(c, "invalid request body")
	}

	// Validate tier
	if req.Tier != "free" && req.Tier != "light" && req.Tier != "premium" {
		return httputil.BadRequest(c, "invalid tier")
	}

	var periodStart *time.Time
	if req.StartsAt != nil {
		t, err := time.Parse(time.RFC3339, *req.StartsAt)
		if err != nil {
			return httputil.BadRequest(c, "invalid starts_at format")
		}
		periodStart = &t
	} else {
		now := time.Now()
		periodStart = &now
	}

	var periodEnd *time.Time
	if req.ExpiresAt != nil {
		t, err := time.Parse(time.RFC3339, *req.ExpiresAt)
		if err != nil {
			return httputil.BadRequest(c, "invalid expires_at format")
		}
		periodEnd = &t
	}

	// Use shared repository to update subscription
	sub := &repository.Subscription{
		UserID:             userID,
		Tier:               req.Tier,
		Status:             "active",
		CurrentPeriodStart: periodStart,
		CurrentPeriodEnd:   periodEnd,
	}

	if err := repository.UpsertSubscription(c.Context(), sub); err != nil {
		return httputil.InternalError(c, "failed to update subscription")
	}

	// Record payment history for admin override
	payment := &repository.PaymentHistory{
		UserID:      userID,
		Provider:    "manual",
		AmountCents: 0,
		Currency:    "USD",
		Tier:        req.Tier,
		PeriodStart: periodStart,
		PeriodEnd:   periodEnd,
		Status:      "completed",
	}
	_ = repository.CreatePaymentHistory(c.Context(), payment)

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

// ListOrders returns all orders (from shared repository)
func (h *AdminHandler) ListOrders(c *fiber.Ctx) error {
	status := c.Query("status", "")
	provider := c.Query("provider", "")
	tier := c.Query("tier", "")
	page := c.QueryInt("page", 1)
	pageSize := c.QueryInt("page_size", 50)
	offset := (page - 1) * pageSize

	// Get orders from shared repository
	ordersWithDetails, total, err := repository.ListOrders(c.Context(), status, provider, tier, pageSize, offset)
	if err != nil {
		return httputil.InternalError(c, "failed to list orders")
	}

	orders := make([]OrderResponse, 0, len(ordersWithDetails))
	for _, o := range ordersWithDetails {
		response := OrderResponse{
			ID:                     o.ID.String(),
			UserID:                 o.UserID.String(),
			UserEmail:              o.UserEmail,
			PlanID:                 o.PlanID,
			PlanName:               o.PlanName,
			Provider:               o.Provider,
			ProviderOrderID:        o.ProviderOrderID,
			ProviderSubscriptionID: o.ProviderSubscriptionID,
			Amount:                 float64(o.AmountCents) / 100.0,
			Currency:               o.Currency,
			Status:                 o.Status,
			CreatedAt:              o.CreatedAt.Format(time.RFC3339),
		}
		if o.CompletedAt != nil {
			s := o.CompletedAt.Format(time.RFC3339)
			response.CompletedAt = &s
		}
		orders = append(orders, response)
	}

	return httputil.SuccessWithMeta(c, orders, httputil.BuildMeta(page, pageSize, int64(total)))
}

// GetOrder returns a single order (from shared repository)
func (h *AdminHandler) GetOrder(c *fiber.Ctx) error {
	orderID, err := uuid.Parse(c.Params("id"))
	if err != nil {
		return httputil.BadRequest(c, "invalid order ID")
	}

	// Get order from shared repository
	order, err := repository.GetOrder(c.Context(), orderID)
	if err != nil {
		return httputil.InternalError(c, "failed to get order")
	}
	if order == nil {
		return httputil.NotFound(c, "order")
	}

	response := OrderResponse{
		ID:                     order.ID.String(),
		UserID:                 order.UserID.String(),
		UserEmail:              order.UserEmail,
		PlanID:                 order.PlanID,
		PlanName:               order.PlanName,
		Provider:               order.Provider,
		ProviderOrderID:        order.ProviderOrderID,
		ProviderSubscriptionID: order.ProviderSubscriptionID,
		Amount:                 float64(order.AmountCents) / 100.0,
		Currency:               order.Currency,
		Status:                 order.Status,
		CreatedAt:              order.CreatedAt.Format(time.RFC3339),
	}
	if order.CompletedAt != nil {
		s := order.CompletedAt.Format(time.RFC3339)
		response.CompletedAt = &s
	}

	return httputil.Success(c, response)
}

// =====================================================
// Plan Management
// =====================================================

// ListPlans returns all subscription plans (from shared repository)
func (h *AdminHandler) ListPlans(c *fiber.Ctx) error {
	// Get plans from shared repository
	plans, err := repository.ListPlans(c.Context())
	if err != nil {
		return httputil.InternalError(c, "failed to list plans")
	}

	result := make([]map[string]interface{}, 0, len(plans))
	for _, p := range plans {
		plan := map[string]interface{}{
			"id":                p.ID,
			"name":              p.Name,
			"tier":              p.Tier,
			"price_monthly":     float64(p.PriceMonthly) / 100.0,
			"currency":          p.Currency,
			"paddle_price_id":   p.PaddlePriceID,
			"apple_product_id":  p.AppleProductID,
			"google_product_id": p.GoogleProductID,
			"is_active":         p.IsActive,
			"features":          p.Features,
			"created_at":        p.CreatedAt.Format(time.RFC3339),
		}
		result = append(result, plan)
	}

	return httputil.Success(c, result)
}

// UpdatePlan updates a subscription plan (via shared repository)
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

	// Use shared repository to update plan fields
	err := repository.UpdatePlanFields(c.Context(), planID, req.PaddlePriceID, req.AppleProductID, req.GoogleProductID, req.IsActive)
	if err != nil {
		return httputil.InternalError(c, "failed to update plan")
	}

	return httputil.Success(c, map[string]string{"message": "plan updated"})
}

// =====================================================
// AI Configuration Management
// =====================================================

// AIConfigResponse represents an AI config in admin list
type AIConfigResponse struct {
	Key         string  `json:"key"`
	Value       string  `json:"value"`
	Description *string `json:"description,omitempty"`
	UpdatedAt   string  `json:"updated_at"`
	UpdatedBy   *string `json:"updated_by,omitempty"`
}

// ListAIConfigs returns all AI prompt configurations
func (h *AdminHandler) ListAIConfigs(c *fiber.Ctx) error {
	configs, err := repository.ListAIPromptConfigs(c.Context())
	if err != nil {
		return httputil.InternalError(c, "failed to list AI configs")
	}

	result := make([]AIConfigResponse, 0, len(configs))
	for _, cfg := range configs {
		result = append(result, AIConfigResponse{
			Key:         cfg.Key,
			Value:       cfg.Value,
			Description: cfg.Description,
			UpdatedAt:   cfg.UpdatedAt.Format(time.RFC3339),
			UpdatedBy:   cfg.UpdatedBy,
		})
	}

	return httputil.Success(c, result)
}

// UpdateAIConfig updates a single AI prompt configuration
func (h *AdminHandler) UpdateAIConfig(c *fiber.Ctx) error {
	key := c.Params("key")
	if key == "" {
		return httputil.BadRequest(c, "config key is required")
	}

	var req struct {
		Value string `json:"value"`
	}
	if err := c.BodyParser(&req); err != nil {
		return httputil.BadRequest(c, "invalid request body")
	}

	if req.Value == "" {
		return httputil.BadRequest(c, "value cannot be empty")
	}

	// Get admin email for audit trail
	email := middleware.GetEmail(c)

	err := repository.UpdateAIPromptConfig(c.Context(), key, req.Value, email)
	if err != nil {
		return httputil.InternalError(c, "failed to update AI config")
	}

	return httputil.Success(c, map[string]string{"message": "config updated"})
}

