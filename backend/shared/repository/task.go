// Package repository provides internal APIs for accessing domain data.
// This file provides access to tasks database for cross-domain operations (like AI).
package repository

import (
	"context"
	"encoding/json"
	"fmt"
	"sort"
	"sync"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/csaptu/flow/pkg/config"
)

var (
	tasksPool     *pgxpool.Pool
	tasksPoolOnce sync.Once
	tasksPoolErr  error
)

// InitTasksDB initializes the tasks database connection pool.
// This should be called once at startup by services that need task data access.
func InitTasksDB(cfg *config.Config) error {
	tasksPoolOnce.Do(func() {
		poolConfig, err := pgxpool.ParseConfig(cfg.Databases.Tasks.DSN())
		if err != nil {
			tasksPoolErr = fmt.Errorf("failed to parse tasks db config: %w", err)
			return
		}

		maxConns := cfg.Databases.Tasks.MaxOpenConns
		if maxConns <= 0 {
			maxConns = 10
		}
		minConns := cfg.Databases.Tasks.MaxIdleConns
		if minConns <= 0 {
			minConns = 2
		}
		poolConfig.MaxConns = int32(maxConns)
		poolConfig.MinConns = int32(minConns)
		poolConfig.MaxConnLifetime = cfg.Databases.Tasks.MaxLifetime

		tasksPool, tasksPoolErr = pgxpool.NewWithConfig(context.Background(), poolConfig)
		if tasksPoolErr != nil {
			tasksPoolErr = fmt.Errorf("failed to connect to tasks db: %w", tasksPoolErr)
			return
		}

		if err := tasksPool.Ping(context.Background()); err != nil {
			tasksPoolErr = fmt.Errorf("failed to ping tasks db: %w", err)
			return
		}
	})

	return tasksPoolErr
}

// CloseTasksDB closes the tasks database connection pool.
func CloseTasksDB() {
	if tasksPool != nil {
		tasksPool.Close()
	}
}

// getTasksPool returns the tasks database pool, or nil if not initialized.
func getTasksPool() *pgxpool.Pool {
	return tasksPool
}

// ErrTasksDBNotInitialized is returned when the tasks database is not initialized.
var ErrTasksDBNotInitialized = fmt.Errorf("tasks database not initialized")

// TaskEntity represents an entity extracted from a task (person, place, etc.)
type TaskEntity struct {
	Type  string `json:"type"`
	Value string `json:"value"`
	ID    string `json:"id,omitempty"`
}

// Task represents a task record from the tasks database.
type Task struct {
	ID                   uuid.UUID
	UserID               uuid.UUID
	Title                string  // User's original input
	Description          *string // User's original input
	Status               string
	Priority             int
	DueAt                *time.Time
	HasDueTime           bool
	CompletedAt          *time.Time
	Tags                 []string
	ParentID             *uuid.UUID
	Depth                int
	Complexity           int
	AICleanedTitle       *string // AI cleaned version (null = not cleaned)
	AICleanedDescription *string // AI cleaned version (null = not cleaned)
	AIExtractedDue       bool
	SkipAutoCleanup      bool
	ReminderAt           *time.Time
	Entities             []TaskEntity
	DuplicateOf          []string
	DuplicateResolved    bool
	Version              int
	CreatedAt            time.Time
	UpdatedAt            time.Time
}

// GetDisplayTitle returns the title to display (AI cleaned or user input)
func (t *Task) GetDisplayTitle() string {
	if t.AICleanedTitle != nil && *t.AICleanedTitle != "" {
		return *t.AICleanedTitle
	}
	return t.Title
}

// GetDisplayDescription returns the description to display (AI cleaned or user input)
func (t *Task) GetDisplayDescription() *string {
	if t.AICleanedDescription != nil && *t.AICleanedDescription != "" {
		return t.AICleanedDescription
	}
	return t.Description
}

// GetSubtasks returns all subtasks for a parent task.
func GetSubtasks(ctx context.Context, parentID, userID uuid.UUID) ([]*Task, error) {
	db := getTasksPool()
	if db == nil {
		return nil, ErrTasksDBNotInitialized
	}

	rows, err := db.Query(ctx, `
		SELECT id, user_id, title, description, status, priority,
		       due_at, has_due_time, completed_at, tags, parent_id, depth, COALESCE(complexity, 0),
		       ai_cleaned_title, ai_cleaned_description,
		       COALESCE(ai_extracted_due, false), COALESCE(skip_auto_cleanup, false),
		       version, created_at, updated_at
		FROM tasks
		WHERE parent_id = $1 AND user_id = $2 AND deleted_at IS NULL
		ORDER BY created_at ASC
	`, parentID, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var subtasks []*Task
	for rows.Next() {
		var t Task
		if err := rows.Scan(
			&t.ID, &t.UserID, &t.Title, &t.Description,
			&t.Status, &t.Priority, &t.DueAt, &t.HasDueTime, &t.CompletedAt, &t.Tags,
			&t.ParentID, &t.Depth, &t.Complexity,
			&t.AICleanedTitle, &t.AICleanedDescription, &t.AIExtractedDue,
			&t.SkipAutoCleanup,
			&t.Version, &t.CreatedAt, &t.UpdatedAt,
		); err != nil {
			continue
		}
		subtasks = append(subtasks, &t)
	}

	return subtasks, nil
}

// GetTaskByID returns a task by ID and user ID.
func GetTaskByID(ctx context.Context, taskID, userID uuid.UUID) (*Task, int, error) {
	db := getTasksPool()
	if db == nil {
		return nil, 0, ErrTasksDBNotInitialized
	}

	var t Task
	var childCount int
	var entitiesJSON []byte
	var duplicateOfJSON []byte

	err := db.QueryRow(ctx, `
		SELECT t.id, t.user_id, t.title, t.description, t.status, t.priority,
		       t.due_at, t.has_due_time, t.completed_at, t.tags, t.parent_id, t.depth, COALESCE(t.complexity, 0),
		       t.ai_cleaned_title, t.ai_cleaned_description,
		       COALESCE(t.ai_extracted_due, false), COALESCE(t.skip_auto_cleanup, false),
		       t.ai_entities, COALESCE(t.duplicate_of, '[]'), COALESCE(t.duplicate_resolved, false),
		       t.version, t.created_at, t.updated_at,
		       (SELECT COUNT(*) FROM tasks WHERE parent_id = t.id AND deleted_at IS NULL) as children_count
		FROM tasks t
		WHERE t.id = $1 AND t.user_id = $2 AND t.deleted_at IS NULL
	`, taskID, userID).Scan(
		&t.ID, &t.UserID, &t.Title, &t.Description,
		&t.Status, &t.Priority, &t.DueAt, &t.HasDueTime, &t.CompletedAt, &t.Tags,
		&t.ParentID, &t.Depth, &t.Complexity,
		&t.AICleanedTitle, &t.AICleanedDescription, &t.AIExtractedDue,
		&t.SkipAutoCleanup,
		&entitiesJSON, &duplicateOfJSON, &t.DuplicateResolved,
		&t.Version, &t.CreatedAt, &t.UpdatedAt, &childCount,
	)

	if err == pgx.ErrNoRows {
		return nil, 0, nil
	}
	if err != nil {
		return nil, 0, err
	}

	// Parse entities from JSON
	if len(entitiesJSON) > 0 {
		_ = json.Unmarshal(entitiesJSON, &t.Entities)
	}
	if t.Entities == nil {
		t.Entities = []TaskEntity{}
	}

	// Parse duplicate_of from JSON
	if len(duplicateOfJSON) > 0 {
		_ = json.Unmarshal(duplicateOfJSON, &t.DuplicateOf)
	}
	if t.DuplicateOf == nil {
		t.DuplicateOf = []string{}
	}

	return &t, childCount, nil
}

// GetUserTasks returns tasks for a user (for duplicate checking).
func GetUserTasks(ctx context.Context, userID uuid.UUID, limit int) ([]*Task, error) {
	db := getTasksPool()
	if db == nil {
		return nil, ErrTasksDBNotInitialized
	}

	rows, err := db.Query(ctx, `
		SELECT id, user_id, title, description, status, priority,
		       due_at, has_due_time, completed_at, tags, parent_id, depth, COALESCE(complexity, 0),
		       ai_cleaned_title, ai_cleaned_description,
		       COALESCE(ai_extracted_due, false), COALESCE(skip_auto_cleanup, false),
		       version, created_at, updated_at
		FROM tasks
		WHERE user_id = $1 AND deleted_at IS NULL AND status NOT IN ('completed', 'cancelled')
		ORDER BY created_at DESC
		LIMIT $2
	`, userID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var tasks []*Task
	for rows.Next() {
		var t Task
		if err := rows.Scan(
			&t.ID, &t.UserID, &t.Title, &t.Description,
			&t.Status, &t.Priority, &t.DueAt, &t.HasDueTime, &t.CompletedAt, &t.Tags,
			&t.ParentID, &t.Depth, &t.Complexity,
			&t.AICleanedTitle, &t.AICleanedDescription, &t.AIExtractedDue,
			&t.SkipAutoCleanup,
			&t.Version, &t.CreatedAt, &t.UpdatedAt,
		); err != nil {
			continue
		}
		tasks = append(tasks, &t)
	}

	return tasks, nil
}

// UpdateTaskAIFields updates AI-related fields on a task.
func UpdateTaskAIFields(ctx context.Context, taskID, userID uuid.UUID, updates map[string]interface{}) error {
	db := getTasksPool()
	if db == nil {
		return ErrTasksDBNotInitialized
	}

	// Build dynamic update query
	setClauses := []string{}
	args := []interface{}{}
	argNum := 1

	fieldMap := map[string]string{
		"title":                  "title",
		"description":            "description",
		"ai_cleaned_title":       "ai_cleaned_title",
		"ai_cleaned_description": "ai_cleaned_description",
		"complexity":             "complexity",
		"ai_entities":            "ai_entities",
		"reminder_at":            "reminder_at",
		"due_at":                 "due_at",
		"has_due_time":           "has_due_time",
		"ai_extracted_due":       "ai_extracted_due",
		"duplicate_of":           "duplicate_of",
		"duplicate_resolved":     "duplicate_resolved",
	}

	for key, dbField := range fieldMap {
		if val, ok := updates[key]; ok {
			setClauses = append(setClauses, fmt.Sprintf("%s = $%d", dbField, argNum))
			args = append(args, val)
			argNum++
		}
	}

	if len(setClauses) == 0 {
		return nil
	}

	// Add version increment and timestamp
	setClauses = append(setClauses, "version = version + 1")
	setClauses = append(setClauses, fmt.Sprintf("updated_at = $%d", argNum))
	args = append(args, time.Now())
	argNum++

	// Add WHERE clause args
	args = append(args, taskID, userID)

	query := fmt.Sprintf(
		"UPDATE tasks SET %s WHERE id = $%d AND user_id = $%d AND deleted_at IS NULL",
		joinStrings(setClauses, ", "),
		argNum,
		argNum+1,
	)

	_, err := db.Exec(ctx, query, args...)
	return err
}

// CreateSubtask creates a subtask under a parent task.
func CreateSubtask(ctx context.Context, userID, parentID uuid.UUID, title string, order int) (uuid.UUID, error) {
	db := getTasksPool()
	if db == nil {
		return uuid.Nil, ErrTasksDBNotInitialized
	}

	subtaskID := uuid.New()
	now := time.Now().Add(time.Duration(order) * time.Millisecond) // Ensure ordering

	_, err := db.Exec(ctx, `
		INSERT INTO tasks (id, user_id, title, status, priority, tags, parent_id, depth, ai_entities, version, created_at, updated_at)
		VALUES ($1, $2, $3, 'pending', 0, '{}', $4, 1, '[]', 1, $5, $5)
	`, subtaskID, userID, title, parentID, now)

	if err != nil {
		return uuid.Nil, err
	}

	return subtaskID, nil
}

// GetAIUsage returns AI usage for a user for today.
func GetAIUsage(ctx context.Context, userID uuid.UUID) (map[string]int, error) {
	db := getTasksPool()
	if db == nil {
		return nil, ErrTasksDBNotInitialized
	}

	rows, err := db.Query(ctx, `
		SELECT feature, count FROM ai_usage
		WHERE user_id = $1 AND used_at = CURRENT_DATE
	`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	usage := make(map[string]int)
	for rows.Next() {
		var feature string
		var count int
		if err := rows.Scan(&feature, &count); err != nil {
			continue
		}
		usage[feature] = count
	}

	return usage, nil
}

// IncrementAIUsage increments AI usage counter for a feature.
func IncrementAIUsage(ctx context.Context, userID uuid.UUID, feature string) error {
	db := getTasksPool()
	if db == nil {
		return ErrTasksDBNotInitialized
	}

	_, err := db.Exec(ctx, `
		INSERT INTO ai_usage (user_id, feature, used_at, count)
		VALUES ($1, $2, CURRENT_DATE, 1)
		ON CONFLICT (user_id, feature, used_at)
		DO UPDATE SET count = ai_usage.count + 1
	`, userID, feature)

	return err
}

// SaveAIDraft saves an AI-generated draft.
func SaveAIDraft(ctx context.Context, userID, taskID uuid.UUID, draftType string, content []byte) (uuid.UUID, error) {
	db := getTasksPool()
	if db == nil {
		return uuid.Nil, ErrTasksDBNotInitialized
	}

	var draftID uuid.UUID
	err := db.QueryRow(ctx, `
		INSERT INTO ai_drafts (user_id, task_id, draft_type, content)
		VALUES ($1, $2, $3, $4)
		RETURNING id
	`, userID, taskID, draftType, content).Scan(&draftID)

	return draftID, err
}

// GetPendingAIDrafts returns pending AI drafts for a user.
func GetPendingAIDrafts(ctx context.Context, userID uuid.UUID) ([]map[string]interface{}, error) {
	db := getTasksPool()
	if db == nil {
		return nil, ErrTasksDBNotInitialized
	}

	rows, err := db.Query(ctx, `
		SELECT id, task_id, draft_type, content, created_at
		FROM ai_drafts
		WHERE user_id = $1 AND status = 'draft'
		ORDER BY created_at DESC
	`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var drafts []map[string]interface{}
	for rows.Next() {
		var id, taskID uuid.UUID
		var draftType string
		var content []byte
		var createdAt time.Time

		if err := rows.Scan(&id, &taskID, &draftType, &content, &createdAt); err != nil {
			continue
		}

		drafts = append(drafts, map[string]interface{}{
			"id":         id,
			"task_id":    taskID,
			"type":       draftType,
			"content":    content,
			"created_at": createdAt,
		})
	}

	return drafts, nil
}

// UpdateAIDraftStatus updates the status of an AI draft.
func UpdateAIDraftStatus(ctx context.Context, draftID, userID uuid.UUID, status string) (int64, error) {
	db := getTasksPool()
	if db == nil {
		return 0, ErrTasksDBNotInitialized
	}

	result, err := db.Exec(ctx, `
		UPDATE ai_drafts SET status = $1
		WHERE id = $2 AND user_id = $3 AND status = 'draft'
	`, status, draftID, userID)
	if err != nil {
		return 0, err
	}

	return result.RowsAffected(), nil
}

func joinStrings(strs []string, sep string) string {
	if len(strs) == 0 {
		return ""
	}
	result := strs[0]
	for i := 1; i < len(strs); i++ {
		result += sep + strs[i]
	}
	return result
}

// EntityItem represents an extracted entity with its count
type EntityItem struct {
	Type  string `json:"type"`
	Value string `json:"value"`
	Count int    `json:"count"`
}

// GetUserEntitiesByType returns all unique entity values for a user by entity type.
// Used for normalization during entity extraction.
func GetUserEntitiesByType(ctx context.Context, userID uuid.UUID, entityType string) ([]string, error) {
	db := getTasksPool()
	if db == nil {
		return nil, ErrTasksDBNotInitialized
	}

	// Query distinct entity values from ai_entities JSONB column
	rows, err := db.Query(ctx, `
		SELECT DISTINCT entity->>'value' as value
		FROM tasks, jsonb_array_elements(COALESCE(ai_entities, '[]'::jsonb)) as entity
		WHERE user_id = $1
		  AND deleted_at IS NULL
		  AND entity->>'type' = $2
		  AND entity->>'value' IS NOT NULL
		  AND entity->>'value' != ''
		ORDER BY value
	`, userID, entityType)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var values []string
	for rows.Next() {
		var value string
		if err := rows.Scan(&value); err != nil {
			continue
		}
		values = append(values, value)
	}

	return values, nil
}

// GetAggregatedEntities returns all entities grouped by type with task counts.
// Used for the Smart Lists sidebar.
func GetAggregatedEntities(ctx context.Context, userID uuid.UUID) (map[string][]EntityItem, error) {
	db := getTasksPool()
	if db == nil {
		return nil, ErrTasksDBNotInitialized
	}

	// First, fetch all aliases for this user
	aliasMap := make(map[string]map[string]string) // type -> (alias_value -> canonical_value)
	aliasRows, err := db.Query(ctx, `
		SELECT entity_type, alias_value, canonical_value
		FROM entity_aliases
		WHERE user_id = $1
	`, userID)
	if err == nil {
		defer aliasRows.Close()
		for aliasRows.Next() {
			var entityType, aliasValue, canonicalValue string
			if err := aliasRows.Scan(&entityType, &aliasValue, &canonicalValue); err != nil {
				continue
			}
			if aliasMap[entityType] == nil {
				aliasMap[entityType] = make(map[string]string)
			}
			aliasMap[entityType][aliasValue] = canonicalValue
		}
	}

	// Fetch raw entity counts (only main tasks, not subtasks)
	rows, err := db.Query(ctx, `
		SELECT
			entity->>'type' as type,
			entity->>'value' as value,
			COUNT(DISTINCT t.id) as count
		FROM tasks t, jsonb_array_elements(COALESCE(t.ai_entities, '[]'::jsonb)) as entity
		WHERE t.user_id = $1
		  AND t.deleted_at IS NULL
		  AND t.status != 'cancelled'
		  AND t.parent_id IS NULL
		  AND entity->>'type' IS NOT NULL
		  AND entity->>'value' IS NOT NULL
		  AND entity->>'value' != ''
		GROUP BY entity->>'type', entity->>'value'
		ORDER BY entity->>'type', count DESC, entity->>'value'
	`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	// Aggregate with alias resolution
	// key: "type:canonical_value" -> count
	aggregated := make(map[string]int)
	for rows.Next() {
		var entityType, entityValue string
		var count int
		if err := rows.Scan(&entityType, &entityValue, &count); err != nil {
			continue
		}

		// Resolve alias to canonical value
		canonicalValue := entityValue
		if typeAliases, ok := aliasMap[entityType]; ok {
			if canonical, isAlias := typeAliases[entityValue]; isAlias {
				canonicalValue = canonical
			}
		}

		key := entityType + ":" + canonicalValue
		aggregated[key] += count
	}

	// Build result, excluding aliased values (they're merged into canonical)
	result := make(map[string][]EntityItem)
	for key, count := range aggregated {
		parts := splitFirst(key, ":")
		if len(parts) != 2 {
			continue
		}
		entityType, entityValue := parts[0], parts[1]

		// Skip if this value is an alias (it's already counted under canonical)
		if typeAliases, ok := aliasMap[entityType]; ok {
			if _, isAlias := typeAliases[entityValue]; isAlias {
				continue
			}
		}

		result[entityType] = append(result[entityType], EntityItem{
			Type:  entityType,
			Value: entityValue,
			Count: count,
		})
	}

	// Sort each type by count descending, then by value
	for entityType := range result {
		items := result[entityType]
		sort.Slice(items, func(i, j int) bool {
			if items[i].Count != items[j].Count {
				return items[i].Count > items[j].Count
			}
			return items[i].Value < items[j].Value
		})
		result[entityType] = items
	}

	return result, nil
}

// splitFirst splits a string on the first occurrence of sep
func splitFirst(s, sep string) []string {
	for i := 0; i <= len(s)-len(sep); i++ {
		if s[i:i+len(sep)] == sep {
			return []string{s[:i], s[i+len(sep):]}
		}
	}
	return []string{s}
}
