package tasks

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"time"

	"github.com/gofiber/fiber/v2"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/csaptu/flow/pkg/httputil"
	"github.com/csaptu/flow/pkg/middleware"
	"github.com/csaptu/flow/shared/repository"
)

// SubscriptionHandler handles subscription endpoints
type SubscriptionHandler struct {
	db *pgxpool.Pool
}

// NewSubscriptionHandler creates a new subscription handler
func NewSubscriptionHandler(db *pgxpool.Pool) *SubscriptionHandler {
	return &SubscriptionHandler{db: db}
}

// =====================================================
// Public Plan Endpoints
// =====================================================

// PlanResponse represents a plan for display
type PlanResponse struct {
	ID           string   `json:"id"`
	Name         string   `json:"name"`
	Tier         string   `json:"tier"`
	PriceMonthly float64  `json:"price_monthly"`
	Currency     string   `json:"currency"`
	Features     []string `json:"features"`
	IsPopular    bool     `json:"is_popular,omitempty"`
}

// GetPlans returns available subscription plans (from shared repository)
func (h *SubscriptionHandler) GetPlans(c *fiber.Ctx) error {
	// Get plans from shared repository
	plans, err := repository.ListPlans(c.Context())
	if err != nil {
		return httputil.InternalError(c, "failed to list plans")
	}

	result := make([]PlanResponse, 0, len(plans))
	for _, p := range plans {
		if !p.IsActive {
			continue
		}
		response := PlanResponse{
			ID:           p.ID,
			Name:         p.Name,
			Tier:         p.Tier,
			PriceMonthly: float64(p.PriceMonthly) / 100.0,
			Currency:     p.Currency,
			Features:     p.Features,
			IsPopular:    p.Tier == "light",
		}
		result = append(result, response)
	}

	return httputil.Success(c, result)
}

// =====================================================
// User Subscription Endpoints
// =====================================================

// GetMySubscription returns current user's subscription info (from shared repository)
func (h *SubscriptionHandler) GetMySubscription(c *fiber.Ctx) error {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		return httputil.Unauthorized(c, "")
	}

	// Get subscription from shared repository
	sub, err := repository.GetUserSubscription(c.Context(), userID)
	if err != nil {
		return httputil.InternalError(c, "failed to get subscription")
	}

	// Get usage stats (still uses local AI usage table)
	aiService := &AIService{db: h.db}
	usageStats, _ := aiService.GetUsageStats(c.Context(), userID)

	response := map[string]interface{}{
		"tier":  sub.Tier,
		"usage": usageStats,
	}

	if sub.CurrentPeriodStart != nil {
		response["started_at"] = sub.CurrentPeriodStart.Format(time.RFC3339)
	}
	if sub.CurrentPeriodEnd != nil {
		response["expires_at"] = sub.CurrentPeriodEnd.Format(time.RFC3339)
		response["is_active"] = sub.CurrentPeriodEnd.After(time.Now())
	} else if sub.Tier != "free" {
		response["is_active"] = sub.Status == "active"
	}
	if sub.Provider != nil {
		response["provider"] = *sub.Provider
	}

	return httputil.Success(c, response)
}

// CreateCheckout initiates a subscription checkout with Paddle (via shared repository)
func (h *SubscriptionHandler) CreateCheckout(c *fiber.Ctx) error {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		return httputil.Unauthorized(c, "")
	}

	var req struct {
		PlanID    string `json:"plan_id"`
		ReturnURL string `json:"return_url,omitempty"`
	}
	if err := c.BodyParser(&req); err != nil {
		return httputil.BadRequest(c, "invalid request body")
	}

	// Get plan details from shared repository
	plan, err := repository.GetPlan(c.Context(), req.PlanID)
	if err != nil {
		return httputil.InternalError(c, "failed to get plan")
	}
	if plan == nil || !plan.IsActive {
		return httputil.NotFound(c, "plan")
	}

	if plan.PaddlePriceID == nil || *plan.PaddlePriceID == "" {
		return httputil.BadRequest(c, "plan not available for online purchase")
	}

	// Create pending order via shared repository
	order := &repository.Order{
		UserID:      userID,
		PlanID:      req.PlanID,
		Provider:    "paddle",
		AmountCents: plan.PriceMonthly,
		Currency:    plan.Currency,
		Status:      "pending",
	}

	if err := repository.CreateOrder(c.Context(), order); err != nil {
		return httputil.InternalError(c, "failed to create order")
	}

	// Return Paddle checkout info
	return httputil.Success(c, map[string]interface{}{
		"order_id":        order.ID.String(),
		"paddle_price_id": *plan.PaddlePriceID,
		"amount":          float64(plan.PriceMonthly) / 100.0,
		"currency":        plan.Currency,
		"tier":            plan.Tier,
		"return_url":      req.ReturnURL,
	})
}

// =====================================================
// Paddle Webhook Handler
// =====================================================

// PaddleWebhook handles Paddle webhook events
func (h *SubscriptionHandler) PaddleWebhook(c *fiber.Ctx) error {
	// Verify webhook signature
	signature := c.Get("Paddle-Signature")
	webhookSecret := os.Getenv("PADDLE_WEBHOOK_SECRET")

	if webhookSecret != "" && signature != "" {
		if !h.verifyPaddleSignature(c.Body(), signature, webhookSecret) {
			return httputil.Unauthorized(c, "invalid signature")
		}
	}

	var event struct {
		EventType string          `json:"event_type"`
		Data      json.RawMessage `json:"data"`
	}

	if err := c.BodyParser(&event); err != nil {
		return httputil.BadRequest(c, "invalid webhook payload")
	}

	switch event.EventType {
	case "subscription.created", "subscription.activated":
		return h.handleSubscriptionCreated(c, event.Data)
	case "subscription.updated":
		return h.handleSubscriptionUpdated(c, event.Data)
	case "subscription.canceled", "subscription.cancelled":
		return h.handleSubscriptionCanceled(c, event.Data)
	case "transaction.completed":
		return h.handleTransactionCompleted(c, event.Data)
	default:
		// Log unknown event type
		fmt.Printf("Unknown Paddle event: %s\n", event.EventType)
	}

	return httputil.Success(c, map[string]string{"status": "received"})
}

func (h *SubscriptionHandler) verifyPaddleSignature(payload []byte, signature, secret string) bool {
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write(payload)
	expected := hex.EncodeToString(mac.Sum(nil))
	return hmac.Equal([]byte(signature), []byte(expected))
}

func (h *SubscriptionHandler) handleSubscriptionCreated(c *fiber.Ctx, data json.RawMessage) error {
	var sub struct {
		ID         string `json:"id"`
		Status     string `json:"status"`
		CustomData struct {
			UserID  string `json:"user_id"`
			OrderID string `json:"order_id"`
		} `json:"custom_data"`
		Items []struct {
			Price struct {
				ID        string `json:"id"`
				ProductID string `json:"product_id"`
			} `json:"price"`
		} `json:"items"`
		CurrentBillingPeriod struct {
			EndsAt string `json:"ends_at"`
		} `json:"current_billing_period"`
	}

	if err := json.Unmarshal(data, &sub); err != nil {
		return httputil.BadRequest(c, "invalid subscription data")
	}

	userID, err := uuid.Parse(sub.CustomData.UserID)
	if err != nil {
		return httputil.BadRequest(c, "invalid user_id")
	}

	// Find plan by paddle price ID via shared repository
	var tier string
	if len(sub.Items) > 0 {
		plan, err := repository.GetPlanByPaddlePrice(c.Context(), sub.Items[0].Price.ID)
		if err == nil && plan != nil {
			tier = plan.Tier
		}
	}
	if tier == "" {
		tier = "free"
	}

	// Parse expiry date
	var periodEnd *time.Time
	if sub.CurrentBillingPeriod.EndsAt != "" {
		t, _ := time.Parse(time.RFC3339, sub.CurrentBillingPeriod.EndsAt)
		periodEnd = &t
	}

	now := time.Now()
	provider := "paddle"

	// Update/create subscription via shared repository
	subscription := &repository.Subscription{
		UserID:                 userID,
		Tier:                   tier,
		Status:                 "active",
		Provider:               &provider,
		ProviderSubscriptionID: &sub.ID,
		CurrentPeriodStart:     &now,
		CurrentPeriodEnd:       periodEnd,
	}

	if err := repository.UpsertSubscription(c.Context(), subscription); err != nil {
		fmt.Printf("Error updating subscription: %v\n", err)
	}

	// Update order if exists
	if sub.CustomData.OrderID != "" {
		orderID, _ := uuid.Parse(sub.CustomData.OrderID)
		_ = repository.UpdateOrderStatus(c.Context(), orderID, "completed", &sub.ID)
	}

	return httputil.Success(c, map[string]string{"status": "processed"})
}

func (h *SubscriptionHandler) handleSubscriptionUpdated(c *fiber.Ctx, data json.RawMessage) error {
	var sub struct {
		ID         string `json:"id"`
		Status     string `json:"status"`
		CustomData struct {
			UserID string `json:"user_id"`
		} `json:"custom_data"`
		CurrentBillingPeriod struct {
			EndsAt string `json:"ends_at"`
		} `json:"current_billing_period"`
	}

	if err := json.Unmarshal(data, &sub); err != nil {
		return httputil.BadRequest(c, "invalid subscription data")
	}

	// Parse expiry date
	var periodEnd *time.Time
	if sub.CurrentBillingPeriod.EndsAt != "" {
		t, _ := time.Parse(time.RFC3339, sub.CurrentBillingPeriod.EndsAt)
		periodEnd = &t
	}

	// Update subscription period via shared repository
	if err := repository.UpdateSubscriptionPeriod(c.Context(), sub.ID, periodEnd); err != nil {
		fmt.Printf("Error updating subscription: %v\n", err)
	}

	return httputil.Success(c, map[string]string{"status": "processed"})
}

func (h *SubscriptionHandler) handleSubscriptionCanceled(c *fiber.Ctx, data json.RawMessage) error {
	var sub struct {
		ID         string `json:"id"`
		CustomData struct {
			UserID string `json:"user_id"`
		} `json:"custom_data"`
		CanceledAt string `json:"canceled_at"`
	}

	if err := json.Unmarshal(data, &sub); err != nil {
		return httputil.BadRequest(c, "invalid subscription data")
	}

	// Cancel subscription via shared repository
	if err := repository.CancelSubscriptionByProviderID(c.Context(), sub.ID); err != nil {
		fmt.Printf("Error canceling subscription: %v\n", err)
	}

	return httputil.Success(c, map[string]string{"status": "processed"})
}

func (h *SubscriptionHandler) handleTransactionCompleted(c *fiber.Ctx, data json.RawMessage) error {
	var txn struct {
		ID         string `json:"id"`
		Status     string `json:"status"`
		CustomData struct {
			UserID  string `json:"user_id"`
			OrderID string `json:"order_id"`
		} `json:"custom_data"`
		Details struct {
			Totals struct {
				Total    string `json:"total"`
				Currency string `json:"currency_code"`
			} `json:"totals"`
		} `json:"details"`
		SubscriptionID string `json:"subscription_id"`
	}

	if err := json.Unmarshal(data, &txn); err != nil {
		return httputil.BadRequest(c, "invalid transaction data")
	}

	// Update order if exists via shared repository
	if txn.CustomData.OrderID != "" {
		orderID, _ := uuid.Parse(txn.CustomData.OrderID)
		_ = repository.UpdateOrderStatus(c.Context(), orderID, "completed", &txn.SubscriptionID)
	}

	return httputil.Success(c, map[string]string{"status": "processed"})
}

// CancelSubscription cancels the current user's subscription (via shared repository)
func (h *SubscriptionHandler) CancelSubscription(c *fiber.Ctx) error {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		return httputil.Unauthorized(c, "")
	}

	// Check if user has a subscription via shared repository
	sub, err := repository.GetUserSubscription(c.Context(), userID)
	if err != nil {
		return httputil.InternalError(c, "failed to get subscription")
	}
	if sub.Tier == "free" {
		return httputil.NotFound(c, "subscription")
	}

	// TODO: Call Paddle API to cancel subscription
	// For now, just mark as cancelled in database
	// In production: paddle.Subscriptions.Cancel(sub.ProviderSubscriptionID)

	// Cancel via shared repository
	if err := repository.CancelSubscription(c.Context(), userID); err != nil {
		return httputil.InternalError(c, "failed to cancel subscription")
	}

	return httputil.Success(c, map[string]string{
		"message": "subscription cancelled",
		"note":    "you will retain access until the end of your billing period",
	})
}
