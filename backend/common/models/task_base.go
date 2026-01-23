package models

import (
	"time"

	"github.com/google/uuid"
)

// TaskBase contains fields shared by ALL task-like entities.
// Both Tasks domain (personal tasks) and Projects domain (WBS nodes) extend this.
type TaskBase struct {
	ID          uuid.UUID  `json:"id" db:"id"`
	UserID      uuid.UUID  `json:"user_id" db:"user_id"`
	Title       string     `json:"title" db:"title"`         // User's original input
	Description *string    `json:"description,omitempty" db:"description"` // User's original input
	Status      Status     `json:"status" db:"status"`
	Priority    Priority   `json:"priority" db:"priority"`
	Complexity  int        `json:"complexity" db:"complexity"` // 1-10 scale
	StartDate   *time.Time `json:"start_date,omitempty" db:"start_date"`
	DueAt       *time.Time `json:"due_at,omitempty" db:"due_at"`         // Full timestamp with timezone
	HasDueTime  bool       `json:"has_due_time" db:"has_due_time"`       // true = specific time matters
	CompletedAt *time.Time `json:"completed_at,omitempty" db:"completed_at"`
	Tags        []string   `json:"tags,omitempty" db:"tags"`
	CreatedAt   time.Time  `json:"created_at" db:"created_at"`
	UpdatedAt   time.Time  `json:"updated_at" db:"updated_at"`
	DeletedAt   *time.Time `json:"deleted_at,omitempty" db:"deleted_at"`
}

// TagsArray returns the tags as a PostgreSQL array string
func (t *TaskBase) TagsArray() []string {
	if t.Tags == nil {
		return []string{}
	}
	return t.Tags
}

// IsCompleted returns true if the task is completed
func (t *TaskBase) IsCompleted() bool {
	return t.Status == StatusCompleted
}

// IsOverdue returns true if the task is past its due date and not completed
// If HasDueTime is true, checks if the specific datetime has passed
// If HasDueTime is false (date-only), only overdue if the date is before today (not including today)
func (t *TaskBase) IsOverdue() bool {
	if t.DueAt == nil || t.IsCompleted() {
		return false
	}

	now := time.Now()

	// If specific time is set, check if that exact time has passed
	if t.HasDueTime {
		return now.After(*t.DueAt)
	}

	// If no specific time (date-only), only overdue if date is strictly before today
	today := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, now.Location())
	dueDate := time.Date(t.DueAt.Year(), t.DueAt.Month(), t.DueAt.Day(), 0, 0, 0, 0, now.Location())
	return dueDate.Before(today)
}

// Progress returns the completion percentage (now based on subtasks, not steps)
func (t *TaskBase) Progress() float64 {
	if t.IsCompleted() {
		return 100.0
	}
	return 0.0
}
