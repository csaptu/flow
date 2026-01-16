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

// GetPlans returns available subscription plans
func (h *SubscriptionHandler) GetPlans(c *fiber.Ctx) error {
	rows, err := h.db.Query(c.Context(), `
		SELECT id, name, tier, price_monthly, currency, features
		FROM subscription_plans
		WHERE is_active = true
		ORDER BY price_monthly ASC
	`)
	if err != nil {
		return httputil.InternalError(c, "database error")
	}
	defer rows.Close()

	plans := make([]PlanResponse, 0)
	for rows.Next() {
		var p PlanResponse
		var features []byte

		if err := rows.Scan(&p.ID, &p.Name, &p.Tier, &p.PriceMonthly, &p.Currency, &features); err != nil {
			continue
		}

		json.Unmarshal(features, &p.Features)
		p.IsPopular = p.Tier == "light" // Mark Light as popular

		plans = append(plans, p)
	}

	return httputil.Success(c, plans)
}

// =====================================================
// User Subscription Endpoints
// =====================================================

// GetMySubscription returns current user's subscription info
func (h *SubscriptionHandler) GetMySubscription(c *fiber.Ctx) error {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		return httputil.Unauthorized(c, "")
	}

	var tier, planID string
	var startedAt, expiresAt *time.Time
	var provider *string

	err = h.db.QueryRow(c.Context(), `
		SELECT COALESCE(tier, 'free'), plan_id, started_at, expires_at, provider
		FROM user_subscriptions
		WHERE user_id = $1
	`, userID).Scan(&tier, &planID, &startedAt, &expiresAt, &provider)

	if err != nil {
		// No subscription record, default to free
		tier = "free"
	}

	// Get usage stats
	aiService := &AIService{db: h.db}
	usageStats, _ := aiService.GetUsageStats(c.Context(), userID)

	response := map[string]interface{}{
		"tier":    tier,
		"plan_id": planID,
		"usage":   usageStats,
	}

	if startedAt != nil {
		response["started_at"] = startedAt.Format(time.RFC3339)
	}
	if expiresAt != nil {
		response["expires_at"] = expiresAt.Format(time.RFC3339)
		response["is_active"] = expiresAt.After(time.Now())
	} else if tier != "free" {
		response["is_active"] = true
	}
	if provider != nil {
		response["provider"] = *provider
	}

	return httputil.Success(c, response)
}

// CreateCheckout initiates a subscription checkout with Paddle
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

	// Get plan details
	var paddlePriceID *string
	var price float64
	var tier string

	err = h.db.QueryRow(c.Context(), `
		SELECT paddle_price_id, price_monthly, tier
		FROM subscription_plans
		WHERE id = $1 AND is_active = true
	`, req.PlanID).Scan(&paddlePriceID, &price, &tier)

	if err != nil {
		return httputil.NotFound(c, "plan")
	}

	if paddlePriceID == nil || *paddlePriceID == "" {
		return httputil.BadRequest(c, "plan not available for online purchase")
	}

	// Create pending order
	orderID := uuid.New()
	_, err = h.db.Exec(c.Context(), `
		INSERT INTO orders (id, user_id, plan_id, provider, amount, currency, status)
		VALUES ($1, $2, $3, 'paddle', $4, 'USD', 'pending')
	`, orderID, userID, req.PlanID, price)

	if err != nil {
		return httputil.InternalError(c, "failed to create order")
	}

	// Return Paddle checkout info
	// In production, you might call Paddle API to create a checkout session
	// For now, return the price ID for client-side Paddle.js
	return httputil.Success(c, map[string]interface{}{
		"order_id":        orderID.String(),
		"paddle_price_id": *paddlePriceID,
		"amount":          price,
		"currency":        "USD",
		"tier":            tier,
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

	// Find plan by paddle price ID
	var planID, tier string
	if len(sub.Items) > 0 {
		h.db.QueryRow(c.Context(),
			"SELECT id, tier FROM subscription_plans WHERE paddle_price_id = $1",
			sub.Items[0].Price.ID,
		).Scan(&planID, &tier)
	}

	// Parse expiry date
	var expiresAt *time.Time
	if sub.CurrentBillingPeriod.EndsAt != "" {
		t, _ := time.Parse(time.RFC3339, sub.CurrentBillingPeriod.EndsAt)
		expiresAt = &t
	}

	now := time.Now()

	// Update/create subscription
	_, err = h.db.Exec(c.Context(), `
		INSERT INTO user_subscriptions (user_id, tier, plan_id, provider, provider_subscription_id, started_at, expires_at, created_at, updated_at)
		VALUES ($1, $2, $3, 'paddle', $4, $5, $6, $5, $5)
		ON CONFLICT (user_id) DO UPDATE SET
			tier = $2,
			plan_id = $3,
			provider = 'paddle',
			provider_subscription_id = $4,
			started_at = COALESCE(user_subscriptions.started_at, $5),
			expires_at = $6,
			updated_at = $5
	`, userID, tier, planID, sub.ID, now, expiresAt)

	if err != nil {
		fmt.Printf("Error updating subscription: %v\n", err)
	}

	// Update order if exists
	if sub.CustomData.OrderID != "" {
		orderID, _ := uuid.Parse(sub.CustomData.OrderID)
		h.db.Exec(c.Context(), `
			UPDATE orders SET
				status = 'completed',
				provider_subscription_id = $1,
				completed_at = $2
			WHERE id = $3
		`, sub.ID, now, orderID)
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
	var expiresAt *time.Time
	if sub.CurrentBillingPeriod.EndsAt != "" {
		t, _ := time.Parse(time.RFC3339, sub.CurrentBillingPeriod.EndsAt)
		expiresAt = &t
	}

	_, err := h.db.Exec(c.Context(), `
		UPDATE user_subscriptions SET
			expires_at = $1,
			updated_at = NOW()
		WHERE provider_subscription_id = $2
	`, expiresAt, sub.ID)

	if err != nil {
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

	now := time.Now()

	// Mark subscription as cancelled (will expire at end of period)
	_, err := h.db.Exec(c.Context(), `
		UPDATE user_subscriptions SET
			cancelled_at = $1,
			updated_at = $1
		WHERE provider_subscription_id = $2
	`, now, sub.ID)

	if err != nil {
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

	now := time.Now()

	// Update order if exists
	if txn.CustomData.OrderID != "" {
		orderID, _ := uuid.Parse(txn.CustomData.OrderID)
		h.db.Exec(c.Context(), `
			UPDATE orders SET
				status = 'completed',
				provider_order_id = $1,
				provider_subscription_id = $2,
				completed_at = $3
			WHERE id = $4
		`, txn.ID, txn.SubscriptionID, now, orderID)
	}

	return httputil.Success(c, map[string]string{"status": "processed"})
}

// CancelSubscription cancels the current user's subscription
func (h *SubscriptionHandler) CancelSubscription(c *fiber.Ctx) error {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		return httputil.Unauthorized(c, "")
	}

	var req struct {
		Reason string `json:"reason,omitempty"`
	}
	_ = c.BodyParser(&req)

	now := time.Now()

	// Get subscription info
	var providerSubID *string
	var provider *string
	err = h.db.QueryRow(c.Context(),
		"SELECT provider_subscription_id, provider FROM user_subscriptions WHERE user_id = $1",
		userID,
	).Scan(&providerSubID, &provider)

	if err != nil {
		return httputil.NotFound(c, "subscription")
	}

	// TODO: Call Paddle API to cancel subscription
	// For now, just mark as cancelled in database
	// In production: paddle.Subscriptions.Cancel(providerSubID)

	_, err = h.db.Exec(c.Context(), `
		UPDATE user_subscriptions SET
			cancelled_at = $1,
			cancel_reason = $2,
			updated_at = $1
		WHERE user_id = $3
	`, now, req.Reason, userID)

	if err != nil {
		return httputil.InternalError(c, "failed to cancel subscription")
	}

	return httputil.Success(c, map[string]string{
		"message": "subscription cancelled",
		"note":    "you will retain access until the end of your billing period",
	})
}
