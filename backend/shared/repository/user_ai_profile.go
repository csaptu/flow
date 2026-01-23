package repository

import (
	"context"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

// UserAIProfile represents a user's AI context profile
type UserAIProfile struct {
	UserID uuid.UUID

	// Editable fields (admin can modify)
	IdentitySummary      *string
	CommunicationStyle   *string
	WorkContext          *string
	PersonalContext      *string
	SocialGraph          *string
	LocationsContext     *string
	RoutinePatterns      *string
	TaskStylePreferences *string
	GoalsAndPriorities   *string

	// Auto-generated fields (refreshed by AI)
	RecentActivitySummary *string
	CurrentFocus          *string
	UpcomingCommitments   *string

	// Refresh tracking
	LastRefreshedAt   time.Time
	RefreshTrigger    *string
	TasksSinceRefresh int

	CreatedAt time.Time
	UpdatedAt time.Time
}

// GetUserAIProfile retrieves a user's AI profile by user ID
func GetUserAIProfile(ctx context.Context, userID uuid.UUID) (*UserAIProfile, error) {
	db := getPool()

	var p UserAIProfile
	err := db.QueryRow(ctx, `
		SELECT user_id,
		       identity_summary, communication_style, work_context, personal_context,
		       social_graph, locations_context, routine_patterns, task_style_preferences,
		       goals_and_priorities, recent_activity_summary, current_focus, upcoming_commitments,
		       last_refreshed_at, refresh_trigger, tasks_since_refresh,
		       created_at, updated_at
		FROM user_ai_profiles
		WHERE user_id = $1
	`, userID).Scan(
		&p.UserID,
		&p.IdentitySummary, &p.CommunicationStyle, &p.WorkContext, &p.PersonalContext,
		&p.SocialGraph, &p.LocationsContext, &p.RoutinePatterns, &p.TaskStylePreferences,
		&p.GoalsAndPriorities, &p.RecentActivitySummary, &p.CurrentFocus, &p.UpcomingCommitments,
		&p.LastRefreshedAt, &p.RefreshTrigger, &p.TasksSinceRefresh,
		&p.CreatedAt, &p.UpdatedAt,
	)

	if err == pgx.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}

	return &p, nil
}

// UpsertUserAIProfile creates or updates a user's AI profile
func UpsertUserAIProfile(ctx context.Context, profile *UserAIProfile) error {
	db := getPool()

	_, err := db.Exec(ctx, `
		INSERT INTO user_ai_profiles (
			user_id,
			identity_summary, communication_style, work_context, personal_context,
			social_graph, locations_context, routine_patterns, task_style_preferences,
			goals_and_priorities, recent_activity_summary, current_focus, upcoming_commitments,
			last_refreshed_at, refresh_trigger, tasks_since_refresh,
			created_at, updated_at
		) VALUES (
			$1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, NOW(), NOW()
		)
		ON CONFLICT (user_id) DO UPDATE SET
			identity_summary = EXCLUDED.identity_summary,
			communication_style = EXCLUDED.communication_style,
			work_context = EXCLUDED.work_context,
			personal_context = EXCLUDED.personal_context,
			social_graph = EXCLUDED.social_graph,
			locations_context = EXCLUDED.locations_context,
			routine_patterns = EXCLUDED.routine_patterns,
			task_style_preferences = EXCLUDED.task_style_preferences,
			goals_and_priorities = EXCLUDED.goals_and_priorities,
			recent_activity_summary = EXCLUDED.recent_activity_summary,
			current_focus = EXCLUDED.current_focus,
			upcoming_commitments = EXCLUDED.upcoming_commitments,
			last_refreshed_at = EXCLUDED.last_refreshed_at,
			refresh_trigger = EXCLUDED.refresh_trigger,
			tasks_since_refresh = EXCLUDED.tasks_since_refresh,
			updated_at = NOW()
	`,
		profile.UserID,
		profile.IdentitySummary, profile.CommunicationStyle, profile.WorkContext, profile.PersonalContext,
		profile.SocialGraph, profile.LocationsContext, profile.RoutinePatterns, profile.TaskStylePreferences,
		profile.GoalsAndPriorities, profile.RecentActivitySummary, profile.CurrentFocus, profile.UpcomingCommitments,
		profile.LastRefreshedAt, profile.RefreshTrigger, profile.TasksSinceRefresh,
	)

	return err
}

// ValidProfileFields defines which fields can be updated individually
var ValidProfileFields = map[string]bool{
	"identity_summary":        true,
	"communication_style":     true,
	"work_context":            true,
	"personal_context":        true,
	"social_graph":            true,
	"locations_context":       true,
	"routine_patterns":        true,
	"task_style_preferences":  true,
	"goals_and_priorities":    true,
	"recent_activity_summary": true,
	"current_focus":           true,
	"upcoming_commitments":    true,
}

// UpdateUserAIProfileField updates a single field in the user's AI profile
func UpdateUserAIProfileField(ctx context.Context, userID uuid.UUID, field, value string) error {
	db := getPool()

	// Validate field name to prevent SQL injection
	if !ValidProfileFields[field] {
		return fmt.Errorf("invalid field name: %s", field)
	}

	// First ensure the profile exists
	_, err := db.Exec(ctx, `
		INSERT INTO user_ai_profiles (user_id)
		VALUES ($1)
		ON CONFLICT (user_id) DO NOTHING
	`, userID)
	if err != nil {
		return err
	}

	// Update the specific field
	query := fmt.Sprintf(`
		UPDATE user_ai_profiles
		SET %s = $2, updated_at = NOW()
		WHERE user_id = $1
	`, field)

	_, err = db.Exec(ctx, query, userID, value)
	return err
}

// IncrementTasksSinceRefresh increments the task counter after task completion
func IncrementTasksSinceRefresh(ctx context.Context, userID uuid.UUID) error {
	db := getPool()

	_, err := db.Exec(ctx, `
		UPDATE user_ai_profiles
		SET tasks_since_refresh = tasks_since_refresh + 1, updated_at = NOW()
		WHERE user_id = $1
	`, userID)

	return err
}

// UserNeedingRefresh represents a user that needs profile refresh
type UserNeedingRefresh struct {
	UserID            uuid.UUID
	TasksSinceRefresh int
	HoursSinceRefresh float64
}

// GetUsersNeedingProfileRefresh returns users whose profiles need refreshing
func GetUsersNeedingProfileRefresh(ctx context.Context, taskThreshold int, hoursSinceRefresh int) ([]UserNeedingRefresh, error) {
	db := getPool()

	rows, err := db.Query(ctx, `
		SELECT user_id, tasks_since_refresh,
		       EXTRACT(EPOCH FROM (NOW() - last_refreshed_at)) / 3600 as hours_since_refresh
		FROM user_ai_profiles
		WHERE tasks_since_refresh >= $1
		   OR last_refreshed_at < NOW() - make_interval(hours => $2)
		ORDER BY tasks_since_refresh DESC
		LIMIT 100
	`, taskThreshold, hoursSinceRefresh)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var users []UserNeedingRefresh
	for rows.Next() {
		var u UserNeedingRefresh
		err := rows.Scan(&u.UserID, &u.TasksSinceRefresh, &u.HoursSinceRefresh)
		if err != nil {
			continue
		}
		users = append(users, u)
	}

	return users, nil
}

// ResetRefreshTracking resets the refresh tracking after a successful refresh
func ResetRefreshTracking(ctx context.Context, userID uuid.UUID, trigger string) error {
	db := getPool()

	_, err := db.Exec(ctx, `
		UPDATE user_ai_profiles
		SET last_refreshed_at = NOW(),
		    refresh_trigger = $2,
		    tasks_since_refresh = 0,
		    updated_at = NOW()
		WHERE user_id = $1
	`, userID, trigger)

	return err
}

// CreateEmptyProfile creates an empty profile for a user if it doesn't exist
func CreateEmptyProfile(ctx context.Context, userID uuid.UUID) error {
	db := getPool()

	_, err := db.Exec(ctx, `
		INSERT INTO user_ai_profiles (user_id)
		VALUES ($1)
		ON CONFLICT (user_id) DO NOTHING
	`, userID)

	return err
}

// TaskSummary represents a simplified task for profile analysis
type TaskSummary struct {
	ID          uuid.UUID
	Title       string
	Description *string
	Status      string
	Priority    int
	DueAt       *string // Formatted due date string for display
	CompletedAt *string
	Tags        []string
	CreatedAt   string
}

// GetRecentTasksForProfile retrieves recent tasks for AI profile analysis
func GetRecentTasksForProfile(ctx context.Context, userID uuid.UUID, daysToAnalyze, maxTasks int) ([]TaskSummary, error) {
	db := getTasksPool()
	if db == nil {
		return nil, ErrTasksDBNotInitialized
	}

	rows, err := db.Query(ctx, `
		SELECT id, title, description, status, priority,
		       to_char(due_at, 'YYYY-MM-DD') as due_at,
		       to_char(completed_at, 'YYYY-MM-DD"T"HH24:MI:SS"Z"') as completed_at,
		       tags,
		       to_char(created_at, 'YYYY-MM-DD"T"HH24:MI:SS"Z"') as created_at
		FROM tasks
		WHERE user_id = $1
		  AND deleted_at IS NULL
		  AND created_at > NOW() - make_interval(days => $2)
		ORDER BY created_at DESC
		LIMIT $3
	`, userID, daysToAnalyze, maxTasks)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var tasks []TaskSummary
	for rows.Next() {
		var t TaskSummary
		err := rows.Scan(&t.ID, &t.Title, &t.Description, &t.Status, &t.Priority,
			&t.DueAt, &t.CompletedAt, &t.Tags, &t.CreatedAt)
		if err != nil {
			continue
		}
		tasks = append(tasks, t)
	}

	return tasks, nil
}
