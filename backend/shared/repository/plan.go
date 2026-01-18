package repository

import (
	"context"
	"encoding/json"
	"time"

	"github.com/jackc/pgx/v5"
)

// Plan represents a subscription plan
type Plan struct {
	ID              string
	Name            string
	Tier            string
	PriceMonthly    int      // cents
	PriceYearly     *int     // cents, nullable
	Currency        string
	Features        []string
	AICallsPerDay   int      // -1 means unlimited
	PaddlePriceID   *string
	AppleProductID  *string
	GoogleProductID *string
	IsActive        bool
	CreatedAt       time.Time
	UpdatedAt       time.Time
}

// ListPlans returns all active subscription plans.
func ListPlans(ctx context.Context) ([]Plan, error) {
	db := getPool()

	rows, err := db.Query(ctx, `
		SELECT id, name, tier, price_monthly_cents, price_yearly_cents, currency,
		       features, ai_calls_per_day, paddle_price_id, apple_product_id, google_product_id,
		       is_active, created_at, updated_at
		FROM subscription_plans
		WHERE is_active = true
		ORDER BY price_monthly_cents ASC
	`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var plans []Plan
	for rows.Next() {
		var p Plan
		var features []byte

		err := rows.Scan(
			&p.ID, &p.Name, &p.Tier, &p.PriceMonthly, &p.PriceYearly, &p.Currency,
			&features, &p.AICallsPerDay, &p.PaddlePriceID, &p.AppleProductID, &p.GoogleProductID,
			&p.IsActive, &p.CreatedAt, &p.UpdatedAt,
		)
		if err != nil {
			continue
		}

		// Parse features JSON
		if len(features) > 0 {
			json.Unmarshal(features, &p.Features)
		}
		if p.Features == nil {
			p.Features = []string{}
		}

		plans = append(plans, p)
	}

	return plans, nil
}

// GetPlan returns a specific plan by ID.
func GetPlan(ctx context.Context, planID string) (*Plan, error) {
	db := getPool()

	var p Plan
	var features []byte

	err := db.QueryRow(ctx, `
		SELECT id, name, tier, price_monthly_cents, price_yearly_cents, currency,
		       features, ai_calls_per_day, paddle_price_id, apple_product_id, google_product_id,
		       is_active, created_at, updated_at
		FROM subscription_plans
		WHERE id = $1
	`, planID).Scan(
		&p.ID, &p.Name, &p.Tier, &p.PriceMonthly, &p.PriceYearly, &p.Currency,
		&features, &p.AICallsPerDay, &p.PaddlePriceID, &p.AppleProductID, &p.GoogleProductID,
		&p.IsActive, &p.CreatedAt, &p.UpdatedAt,
	)

	if err == pgx.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}

	// Parse features JSON
	if len(features) > 0 {
		json.Unmarshal(features, &p.Features)
	}
	if p.Features == nil {
		p.Features = []string{}
	}

	return &p, nil
}

// GetPlanByPaddlePrice returns a plan by its Paddle price ID.
func GetPlanByPaddlePrice(ctx context.Context, paddlePriceID string) (*Plan, error) {
	db := getPool()

	var p Plan
	var features []byte

	err := db.QueryRow(ctx, `
		SELECT id, name, tier, price_monthly_cents, price_yearly_cents, currency,
		       features, ai_calls_per_day, paddle_price_id, apple_product_id, google_product_id,
		       is_active, created_at, updated_at
		FROM subscription_plans
		WHERE paddle_price_id = $1
	`, paddlePriceID).Scan(
		&p.ID, &p.Name, &p.Tier, &p.PriceMonthly, &p.PriceYearly, &p.Currency,
		&features, &p.AICallsPerDay, &p.PaddlePriceID, &p.AppleProductID, &p.GoogleProductID,
		&p.IsActive, &p.CreatedAt, &p.UpdatedAt,
	)

	if err == pgx.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}

	if len(features) > 0 {
		json.Unmarshal(features, &p.Features)
	}
	if p.Features == nil {
		p.Features = []string{}
	}

	return &p, nil
}

// UpdatePlan updates a subscription plan.
func UpdatePlan(ctx context.Context, p *Plan) error {
	db := getPool()

	features, _ := json.Marshal(p.Features)

	_, err := db.Exec(ctx, `
		UPDATE subscription_plans SET
			name = $2,
			tier = $3,
			price_monthly_cents = $4,
			price_yearly_cents = $5,
			currency = $6,
			features = $7,
			ai_calls_per_day = $8,
			paddle_price_id = $9,
			apple_product_id = $10,
			google_product_id = $11,
			is_active = $12,
			updated_at = NOW()
		WHERE id = $1
	`, p.ID, p.Name, p.Tier, p.PriceMonthly, p.PriceYearly, p.Currency,
		features, p.AICallsPerDay, p.PaddlePriceID, p.AppleProductID, p.GoogleProductID, p.IsActive)

	return err
}

// UpdatePlanFields updates specific fields of a subscription plan (admin use).
func UpdatePlanFields(ctx context.Context, planID string, paddlePriceID, appleProductID, googleProductID *string, isActive *bool) error {
	db := getPool()

	_, err := db.Exec(ctx, `
		UPDATE subscription_plans SET
			paddle_price_id = COALESCE($2, paddle_price_id),
			apple_product_id = COALESCE($3, apple_product_id),
			google_product_id = COALESCE($4, google_product_id),
			is_active = COALESCE($5, is_active),
			updated_at = NOW()
		WHERE id = $1
	`, planID, paddlePriceID, appleProductID, googleProductID, isActive)

	return err
}
