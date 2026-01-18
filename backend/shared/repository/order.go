package repository

import (
	"context"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

// Order represents a purchase order.
type Order struct {
	ID                     uuid.UUID
	UserID                 uuid.UUID
	PlanID                 string
	Provider               string
	ProviderOrderID        *string
	ProviderSubscriptionID *string
	AmountCents            int
	Currency               string
	Status                 string
	Metadata               *string
	CreatedAt              time.Time
	CompletedAt            *time.Time
	RefundedAt             *time.Time
}

// OrderWithDetails includes user and plan info for admin views.
type OrderWithDetails struct {
	Order
	UserEmail string
	PlanName  string
	PlanTier  string
}

// CreateOrder creates a new order.
func CreateOrder(ctx context.Context, order *Order) error {
	db := getPool()

	if order.ID == uuid.Nil {
		order.ID = uuid.New()
	}

	_, err := db.Exec(ctx, `
		INSERT INTO orders (
			id, user_id, plan_id, provider, provider_order_id, provider_subscription_id,
			amount_cents, currency, status, metadata, created_at
		) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, NOW())
	`, order.ID, order.UserID, order.PlanID, order.Provider,
		order.ProviderOrderID, order.ProviderSubscriptionID,
		order.AmountCents, order.Currency, order.Status, order.Metadata)

	return err
}

// GetOrder returns an order by ID.
func GetOrder(ctx context.Context, orderID uuid.UUID) (*OrderWithDetails, error) {
	db := getPool()

	var o OrderWithDetails
	err := db.QueryRow(ctx, `
		SELECT o.id, o.user_id, o.plan_id, o.provider, o.provider_order_id,
		       o.provider_subscription_id, o.amount_cents, o.currency, o.status,
		       o.metadata, o.created_at, o.completed_at, o.refunded_at,
		       u.email, p.name, p.tier
		FROM orders o
		JOIN users u ON o.user_id = u.id
		JOIN subscription_plans p ON o.plan_id = p.id
		WHERE o.id = $1
	`, orderID).Scan(
		&o.ID, &o.UserID, &o.PlanID, &o.Provider, &o.ProviderOrderID,
		&o.ProviderSubscriptionID, &o.AmountCents, &o.Currency, &o.Status,
		&o.Metadata, &o.CreatedAt, &o.CompletedAt, &o.RefundedAt,
		&o.UserEmail, &o.PlanName, &o.PlanTier,
	)

	if err == pgx.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}

	return &o, nil
}

// ListOrders returns paginated orders with optional filters.
func ListOrders(ctx context.Context, status, provider, tier string, limit, offset int) ([]OrderWithDetails, int, error) {
	db := getPool()

	// Build query with filters
	baseQuery := `
		FROM orders o
		JOIN users u ON o.user_id = u.id
		JOIN subscription_plans p ON o.plan_id = p.id
		WHERE 1=1
	`
	args := []interface{}{}
	argNum := 1

	if status != "" {
		baseQuery += fmt.Sprintf(" AND o.status = $%d", argNum)
		args = append(args, status)
		argNum++
	}
	if provider != "" {
		baseQuery += fmt.Sprintf(" AND o.provider = $%d", argNum)
		args = append(args, provider)
		argNum++
	}
	if tier != "" {
		baseQuery += fmt.Sprintf(" AND p.tier = $%d", argNum)
		args = append(args, tier)
		argNum++
	}

	// Get total count
	var total int
	countQuery := "SELECT COUNT(*) " + baseQuery
	err := db.QueryRow(ctx, countQuery, args...).Scan(&total)
	if err != nil {
		return nil, 0, err
	}

	// Get paginated results
	selectQuery := `
		SELECT o.id, o.user_id, o.plan_id, o.provider, o.provider_order_id,
		       o.provider_subscription_id, o.amount_cents, o.currency, o.status,
		       o.metadata, o.created_at, o.completed_at, o.refunded_at,
		       u.email, p.name, p.tier
	` + baseQuery + fmt.Sprintf(" ORDER BY o.created_at DESC LIMIT $%d OFFSET $%d", argNum, argNum+1)
	args = append(args, limit, offset)

	rows, err := db.Query(ctx, selectQuery, args...)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	var orders []OrderWithDetails
	for rows.Next() {
		var o OrderWithDetails
		err := rows.Scan(
			&o.ID, &o.UserID, &o.PlanID, &o.Provider, &o.ProviderOrderID,
			&o.ProviderSubscriptionID, &o.AmountCents, &o.Currency, &o.Status,
			&o.Metadata, &o.CreatedAt, &o.CompletedAt, &o.RefundedAt,
			&o.UserEmail, &o.PlanName, &o.PlanTier,
		)
		if err != nil {
			continue
		}
		orders = append(orders, o)
	}

	return orders, total, nil
}

// UpdateOrderStatus updates order status.
func UpdateOrderStatus(ctx context.Context, orderID uuid.UUID, status string, providerSubID *string) error {
	db := getPool()

	now := time.Now()
	var completedAt *time.Time
	if status == "completed" {
		completedAt = &now
	}

	_, err := db.Exec(ctx, `
		UPDATE orders SET
			status = $2,
			provider_subscription_id = COALESCE($3, provider_subscription_id),
			completed_at = COALESCE($4, completed_at)
		WHERE id = $1
	`, orderID, status, providerSubID, completedAt)

	return err
}

// GetOrderByProviderID finds order by provider order ID.
func GetOrderByProviderID(ctx context.Context, provider, providerOrderID string) (*Order, error) {
	db := getPool()

	var o Order
	err := db.QueryRow(ctx, `
		SELECT id, user_id, plan_id, provider, provider_order_id,
		       provider_subscription_id, amount_cents, currency, status,
		       metadata, created_at, completed_at, refunded_at
		FROM orders
		WHERE provider = $1 AND provider_order_id = $2
	`, provider, providerOrderID).Scan(
		&o.ID, &o.UserID, &o.PlanID, &o.Provider, &o.ProviderOrderID,
		&o.ProviderSubscriptionID, &o.AmountCents, &o.Currency, &o.Status,
		&o.Metadata, &o.CreatedAt, &o.CompletedAt, &o.RefundedAt,
	)

	if err == pgx.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}

	return &o, nil
}
