package repository

import (
	"context"
	"time"

	"github.com/jackc/pgx/v5"
)

// PageContent represents editable page content
type PageContent struct {
	Key       string
	Title     string
	Content   string
	UpdatedAt time.Time
	UpdatedBy *string
}

// GetPageContent retrieves page content by key (public)
func GetPageContent(ctx context.Context, key string) (*PageContent, error) {
	db := getPool()

	var page PageContent
	err := db.QueryRow(ctx, `
		SELECT key, title, content, updated_at, updated_by
		FROM page_contents
		WHERE key = $1
	`, key).Scan(&page.Key, &page.Title, &page.Content, &page.UpdatedAt, &page.UpdatedBy)

	if err == pgx.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}

	return &page, nil
}

// ListPageContents returns all page contents (admin)
func ListPageContents(ctx context.Context) ([]PageContent, error) {
	db := getPool()

	rows, err := db.Query(ctx, `
		SELECT key, title, content, updated_at, updated_by
		FROM page_contents
		ORDER BY key
	`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var pages []PageContent
	for rows.Next() {
		var p PageContent
		err := rows.Scan(&p.Key, &p.Title, &p.Content, &p.UpdatedAt, &p.UpdatedBy)
		if err != nil {
			continue
		}
		pages = append(pages, p)
	}

	return pages, nil
}

// UpdatePageContent updates page content (admin)
func UpdatePageContent(ctx context.Context, key, content, updatedBy string) error {
	db := getPool()

	_, err := db.Exec(ctx, `
		UPDATE page_contents
		SET content = $2, updated_at = NOW(), updated_by = $3
		WHERE key = $1
	`, key, content, updatedBy)

	return err
}

// UpsertPageContent creates or updates page content (admin)
func UpsertPageContent(ctx context.Context, key, title, content, updatedBy string) error {
	db := getPool()

	_, err := db.Exec(ctx, `
		INSERT INTO page_contents (key, title, content, updated_by)
		VALUES ($1, $2, $3, $4)
		ON CONFLICT (key) DO UPDATE
		SET title = EXCLUDED.title,
			content = EXCLUDED.content,
			updated_at = NOW(),
			updated_by = EXCLUDED.updated_by
	`, key, title, content, updatedBy)

	return err
}
