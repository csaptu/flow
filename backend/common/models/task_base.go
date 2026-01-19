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
	Title       string     `json:"title" db:"title"`
	Description *string    `json:"description,omitempty" db:"description"`
	AISummary   *string    `json:"ai_summary,omitempty" db:"ai_summary"`
	Status      Status     `json:"status" db:"status"`
	Priority    Priority   `json:"priority" db:"priority"`
	Complexity  int        `json:"complexity" db:"complexity"` // 1-10 scale
	StartDate   *time.Time `json:"start_date,omitempty" db:"start_date"`
	DueDate     *time.Time `json:"due_date,omitempty" db:"due_date"`
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
func (t *TaskBase) IsOverdue() bool {
	if t.DueDate == nil || t.IsCompleted() {
		return false
	}
	return time.Now().After(*t.DueDate)
}

// Progress returns the completion percentage (now based on subtasks, not steps)
func (t *TaskBase) Progress() float64 {
	if t.IsCompleted() {
		return 100.0
	}
	return 0.0
}
