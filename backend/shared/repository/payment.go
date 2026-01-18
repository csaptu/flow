package repository

import (
	"context"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

// PaymentHistory represents a payment transaction
type PaymentHistory struct {
	ID                    uuid.UUID
	UserID                uuid.UUID
	SubscriptionID        *uuid.UUID
	Provider              string
	ProviderTransactionID *string
	AmountCents           int
	Currency              string
	Tier                  string
	PeriodStart           *time.Time
	PeriodEnd             *time.Time
	Status                string
	FailureReason         *string
	CreatedAt             time.Time
}

// CreatePaymentHistory records a new payment.
func CreatePaymentHistory(ctx context.Context, p *PaymentHistory) error {
	db := getPool()

	if p.ID == uuid.Nil {
		p.ID = uuid.New()
	}

	_, err := db.Exec(ctx, `
		INSERT INTO payment_history (
			id, user_id, subscription_id, provider, provider_transaction_id,
			amount_cents, currency, tier, period_start, period_end, status, failure_reason, created_at
		) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, NOW())
	`, p.ID, p.UserID, p.SubscriptionID, p.Provider, p.ProviderTransactionID,
		p.AmountCents, p.Currency, p.Tier, p.PeriodStart, p.PeriodEnd, p.Status, p.FailureReason)

	return err
}

// GetPaymentHistory returns payment history for a user.
func GetPaymentHistory(ctx context.Context, userID uuid.UUID, limit, offset int) ([]PaymentHistory, int, error) {
	db := getPool()

	// Get total count
	var total int
	err := db.QueryRow(ctx, `
		SELECT COUNT(*) FROM payment_history WHERE user_id = $1
	`, userID).Scan(&total)
	if err != nil {
		return nil, 0, err
	}

	// Get paginated results
	rows, err := db.Query(ctx, `
		SELECT id, user_id, subscription_id, provider, provider_transaction_id,
		       amount_cents, currency, tier, period_start, period_end, status, failure_reason, created_at
		FROM payment_history
		WHERE user_id = $1
		ORDER BY created_at DESC
		LIMIT $2 OFFSET $3
	`, userID, limit, offset)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	var payments []PaymentHistory
	for rows.Next() {
		var p PaymentHistory
		err := rows.Scan(
			&p.ID, &p.UserID, &p.SubscriptionID, &p.Provider, &p.ProviderTransactionID,
			&p.AmountCents, &p.Currency, &p.Tier, &p.PeriodStart, &p.PeriodEnd,
			&p.Status, &p.FailureReason, &p.CreatedAt,
		)
		if err != nil {
			continue
		}
		payments = append(payments, p)
	}

	return payments, total, nil
}

// ListAllPayments returns all payments (admin).
func ListAllPayments(ctx context.Context, limit, offset int, filters map[string]string) ([]PaymentHistory, int, error) {
	db := getPool()

	// Build filter conditions
	conditions := ""
	args := []interface{}{}
	argNum := 1

	if status, ok := filters["status"]; ok && status != "" {
		conditions += " AND status = $" + string(rune('0'+argNum))
		args = append(args, status)
		argNum++
	}
	if provider, ok := filters["provider"]; ok && provider != "" {
		conditions += " AND provider = $" + string(rune('0'+argNum))
		args = append(args, provider)
		argNum++
	}
	if tier, ok := filters["tier"]; ok && tier != "" {
		conditions += " AND tier = $" + string(rune('0'+argNum))
		args = append(args, tier)
		argNum++
	}

	// Get total count
	var total int
	countQuery := "SELECT COUNT(*) FROM payment_history WHERE 1=1" + conditions
	err := db.QueryRow(ctx, countQuery, args...).Scan(&total)
	if err != nil {
		return nil, 0, err
	}

	// Get paginated results
	args = append(args, limit, offset)
	query := `
		SELECT id, user_id, subscription_id, provider, provider_transaction_id,
		       amount_cents, currency, tier, period_start, period_end, status, failure_reason, created_at
		FROM payment_history
		WHERE 1=1` + conditions + `
		ORDER BY created_at DESC
		LIMIT $` + string(rune('0'+argNum)) + ` OFFSET $` + string(rune('0'+argNum+1))

	rows, err := db.Query(ctx, query, args...)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	var payments []PaymentHistory
	for rows.Next() {
		var p PaymentHistory
		err := rows.Scan(
			&p.ID, &p.UserID, &p.SubscriptionID, &p.Provider, &p.ProviderTransactionID,
			&p.AmountCents, &p.Currency, &p.Tier, &p.PeriodStart, &p.PeriodEnd,
			&p.Status, &p.FailureReason, &p.CreatedAt,
		)
		if err != nil {
			continue
		}
		payments = append(payments, p)
	}

	return payments, total, nil
}

// GetPaymentByProviderTxn looks up a payment by provider transaction ID.
func GetPaymentByProviderTxn(ctx context.Context, provider, txnID string) (*PaymentHistory, error) {
	db := getPool()

	var p PaymentHistory
	err := db.QueryRow(ctx, `
		SELECT id, user_id, subscription_id, provider, provider_transaction_id,
		       amount_cents, currency, tier, period_start, period_end, status, failure_reason, created_at
		FROM payment_history
		WHERE provider = $1 AND provider_transaction_id = $2
	`, provider, txnID).Scan(
		&p.ID, &p.UserID, &p.SubscriptionID, &p.Provider, &p.ProviderTransactionID,
		&p.AmountCents, &p.Currency, &p.Tier, &p.PeriodStart, &p.PeriodEnd,
		&p.Status, &p.FailureReason, &p.CreatedAt,
	)

	if err == pgx.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}

	return &p, nil
}

// UpdatePaymentStatus updates the status of a payment.
func UpdatePaymentStatus(ctx context.Context, paymentID uuid.UUID, status string, failureReason *string) error {
	db := getPool()

	_, err := db.Exec(ctx, `
		UPDATE payment_history SET status = $2, failure_reason = $3 WHERE id = $1
	`, paymentID, status, failureReason)

	return err
}
