package repository

import (
	"context"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

// Subscription represents a user's subscription
type Subscription struct {
	ID                     uuid.UUID
	UserID                 uuid.UUID
	Tier                   string
	Status                 string
	Provider               *string
	ProviderSubscriptionID *string
	ProviderCustomerID     *string
	CurrentPeriodStart     *time.Time
	CurrentPeriodEnd       *time.Time
	GracePeriodEnd         *time.Time
	CancelAtPeriodEnd      bool
	CancelledAt            *time.Time
	CreatedAt              time.Time
	UpdatedAt              time.Time
}

// GetUserSubscription returns the subscription for a user.
// Returns a default free subscription if none exists.
func GetUserSubscription(ctx context.Context, userID uuid.UUID) (*Subscription, error) {
	db := getPool()

	var sub Subscription
	err := db.QueryRow(ctx, `
		SELECT id, user_id, tier, status, provider, provider_subscription_id, provider_customer_id,
		       current_period_start, current_period_end, grace_period_end,
		       cancel_at_period_end, cancelled_at, created_at, updated_at
		FROM subscriptions
		WHERE user_id = $1
	`, userID).Scan(
		&sub.ID, &sub.UserID, &sub.Tier, &sub.Status,
		&sub.Provider, &sub.ProviderSubscriptionID, &sub.ProviderCustomerID,
		&sub.CurrentPeriodStart, &sub.CurrentPeriodEnd, &sub.GracePeriodEnd,
		&sub.CancelAtPeriodEnd, &sub.CancelledAt, &sub.CreatedAt, &sub.UpdatedAt,
	)

	if err == pgx.ErrNoRows {
		// Return default free subscription
		return &Subscription{
			UserID:    userID,
			Tier:      "free",
			Status:    "active",
			CreatedAt: time.Now(),
			UpdatedAt: time.Now(),
		}, nil
	}
	if err != nil {
		return nil, err
	}

	return &sub, nil
}

// GetUserTier returns just the tier for a user (common operation).
// Returns "free" if no subscription exists.
func GetUserTier(ctx context.Context, userID uuid.UUID) (string, error) {
	db := getPool()

	var tier string
	err := db.QueryRow(ctx, `
		SELECT tier FROM subscriptions WHERE user_id = $1
	`, userID).Scan(&tier)

	if err == pgx.ErrNoRows {
		return "free", nil
	}
	if err != nil {
		return "", err
	}

	return tier, nil
}

// UpsertSubscription creates or updates a user's subscription.
func UpsertSubscription(ctx context.Context, sub *Subscription) error {
	db := getPool()

	_, err := db.Exec(ctx, `
		INSERT INTO subscriptions (
			id, user_id, tier, status, provider, provider_subscription_id,
			provider_customer_id, current_period_start, current_period_end,
			grace_period_end, cancel_at_period_end, cancelled_at, created_at, updated_at
		) VALUES (
			COALESCE($1, uuid_generate_v4()), $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, NOW(), NOW()
		)
		ON CONFLICT (user_id) DO UPDATE SET
			tier = EXCLUDED.tier,
			status = EXCLUDED.status,
			provider = COALESCE(EXCLUDED.provider, subscriptions.provider),
			provider_subscription_id = COALESCE(EXCLUDED.provider_subscription_id, subscriptions.provider_subscription_id),
			provider_customer_id = COALESCE(EXCLUDED.provider_customer_id, subscriptions.provider_customer_id),
			current_period_start = COALESCE(EXCLUDED.current_period_start, subscriptions.current_period_start),
			current_period_end = COALESCE(EXCLUDED.current_period_end, subscriptions.current_period_end),
			grace_period_end = EXCLUDED.grace_period_end,
			cancel_at_period_end = EXCLUDED.cancel_at_period_end,
			cancelled_at = EXCLUDED.cancelled_at,
			updated_at = NOW()
	`, sub.ID, sub.UserID, sub.Tier, sub.Status, sub.Provider,
		sub.ProviderSubscriptionID, sub.ProviderCustomerID,
		sub.CurrentPeriodStart, sub.CurrentPeriodEnd, sub.GracePeriodEnd,
		sub.CancelAtPeriodEnd, sub.CancelledAt)

	return err
}

// CancelSubscription marks a subscription as cancelled at period end.
func CancelSubscription(ctx context.Context, userID uuid.UUID) error {
	db := getPool()

	_, err := db.Exec(ctx, `
		UPDATE subscriptions
		SET cancel_at_period_end = true, cancelled_at = NOW(), updated_at = NOW()
		WHERE user_id = $1
	`, userID)

	return err
}

// ListSubscriptions returns paginated list of all subscriptions (admin use).
func ListSubscriptions(ctx context.Context, tier string, limit, offset int) ([]Subscription, int, error) {
	db := getPool()

	// Build query with optional tier filter
	countQuery := "SELECT COUNT(*) FROM subscriptions"
	listQuery := `
		SELECT id, user_id, tier, status, provider, provider_subscription_id, provider_customer_id,
		       current_period_start, current_period_end, grace_period_end,
		       cancel_at_period_end, cancelled_at, created_at, updated_at
		FROM subscriptions
	`

	var total int
	var rows pgx.Rows
	var err error

	if tier != "" {
		countQuery += " WHERE tier = $1"
		listQuery += " WHERE tier = $1 ORDER BY created_at DESC LIMIT $2 OFFSET $3"
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
		listQuery += " ORDER BY created_at DESC LIMIT $1 OFFSET $2"
		rows, err = db.Query(ctx, listQuery, limit, offset)
	}
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	var subs []Subscription
	for rows.Next() {
		var sub Subscription
		err := rows.Scan(
			&sub.ID, &sub.UserID, &sub.Tier, &sub.Status,
			&sub.Provider, &sub.ProviderSubscriptionID, &sub.ProviderCustomerID,
			&sub.CurrentPeriodStart, &sub.CurrentPeriodEnd, &sub.GracePeriodEnd,
			&sub.CancelAtPeriodEnd, &sub.CancelledAt, &sub.CreatedAt, &sub.UpdatedAt,
		)
		if err != nil {
			continue
		}
		subs = append(subs, sub)
	}

	return subs, total, nil
}

// GetSubscriptionByProviderID finds subscription by provider subscription ID.
func GetSubscriptionByProviderID(ctx context.Context, providerSubID string) (*Subscription, error) {
	db := getPool()

	var sub Subscription
	err := db.QueryRow(ctx, `
		SELECT id, user_id, tier, status, provider, provider_subscription_id, provider_customer_id,
		       current_period_start, current_period_end, grace_period_end,
		       cancel_at_period_end, cancelled_at, created_at, updated_at
		FROM subscriptions
		WHERE provider_subscription_id = $1
	`, providerSubID).Scan(
		&sub.ID, &sub.UserID, &sub.Tier, &sub.Status,
		&sub.Provider, &sub.ProviderSubscriptionID, &sub.ProviderCustomerID,
		&sub.CurrentPeriodStart, &sub.CurrentPeriodEnd, &sub.GracePeriodEnd,
		&sub.CancelAtPeriodEnd, &sub.CancelledAt, &sub.CreatedAt, &sub.UpdatedAt,
	)

	if err == pgx.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}

	return &sub, nil
}

// UpdateSubscriptionPeriod updates the subscription billing period.
func UpdateSubscriptionPeriod(ctx context.Context, providerSubID string, periodEnd *time.Time) error {
	db := getPool()

	_, err := db.Exec(ctx, `
		UPDATE subscriptions
		SET current_period_end = $1, updated_at = NOW()
		WHERE provider_subscription_id = $2
	`, periodEnd, providerSubID)

	return err
}

// CancelSubscriptionByProviderID cancels by provider subscription ID.
func CancelSubscriptionByProviderID(ctx context.Context, providerSubID string) error {
	db := getPool()

	_, err := db.Exec(ctx, `
		UPDATE subscriptions
		SET cancel_at_period_end = true, cancelled_at = NOW(), updated_at = NOW()
		WHERE provider_subscription_id = $1
	`, providerSubID)

	return err
}
