package models

import (
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/csaptu/flow/common/models"
)

// Task represents a personal task in the tasks domain
// Tasks follow a 2-layer hierarchy: Parent (layer 0) -> Children (layer 1)
// Any deeper hierarchy should graduate to Projects domain
type Task struct {
	models.TaskBase

	// Hierarchy
	ParentID *uuid.UUID `json:"parent_id,omitempty" db:"parent_id"`
	Depth    int        `json:"depth" db:"depth"` // 0 = root, 1 = child (max)

	// Original text (before AI cleanup) - preserves user input for revert
	OriginalTitle       *string `json:"original_title,omitempty" db:"original_title"`
	OriginalDescription *string `json:"original_description,omitempty" db:"original_description"`
	SkipAutoCleanup     bool    `json:"skip_auto_cleanup" db:"skip_auto_cleanup"`

	// Recurrence
	RecurrenceRule *string    `json:"recurrence_rule,omitempty" db:"recurrence_rule"` // RRULE format
	LastOccurrence *time.Time `json:"last_occurrence,omitempty" db:"last_occurrence"`
	NextOccurrence *time.Time `json:"next_occurrence,omitempty" db:"next_occurrence"`

	// Reminder
	ReminderAt *time.Time `json:"reminder_at,omitempty" db:"reminder_at"`

	// AI features
	AICleanedTitle bool     `json:"ai_cleaned_title" db:"ai_cleaned_title"`
	AIExtractedDue bool     `json:"ai_extracted_due" db:"ai_extracted_due"`
	AIDecomposed   bool     `json:"ai_decomposed" db:"ai_decomposed"`
	Complexity     int      `json:"complexity" db:"complexity"` // 1-10 scale from AI

	// Entities extracted by AI
	Entities []TaskEntity `json:"entities,omitempty" db:"entities"`

	// Project promotion tracking
	PromotedToProject *uuid.UUID `json:"promoted_to_project,omitempty" db:"promoted_to_project"`

	// Sync fields
	Version   int        `json:"version" db:"version"`
	DeviceID  *string    `json:"device_id,omitempty" db:"device_id"`
	SyncedAt  *time.Time `json:"synced_at,omitempty" db:"synced_at"`
}

// TaskEntity represents an entity extracted from a task (person, place, etc.)
type TaskEntity struct {
	Type  string `json:"type"`  // person, place, organization, event
	Value string `json:"value"` // The extracted value
	ID    string `json:"id,omitempty"` // Optional reference ID
}

// NewTask creates a new task with default values
func NewTask(userID uuid.UUID, title string) *Task {
	now := time.Now()
	return &Task{
		TaskBase: models.TaskBase{
			ID:        uuid.New(),
			UserID:    userID,
			Title:     title,
			Status:    models.StatusPending,
			Priority:  models.PriorityNone,
			Tags:      []string{},
			AISteps:   []models.TaskStep{},
			CreatedAt: now,
			UpdatedAt: now,
		},
		Depth:    0,
		Entities: []TaskEntity{},
		Version:  1,
	}
}

// CanHaveChildren checks if this task can have child tasks
func (t *Task) CanHaveChildren() bool {
	// Only root tasks (depth 0) can have children
	return t.Depth == 0
}

// IsChild checks if this task is a child task
func (t *Task) IsChild() bool {
	return t.ParentID != nil && t.Depth > 0
}

// SetParent sets the parent task and updates depth
func (t *Task) SetParent(parentID uuid.UUID, parentDepth int) error {
	// Enforce 2-layer limit
	if parentDepth >= 1 {
		return ErrMaxDepthExceeded
	}

	t.ParentID = &parentID
	t.Depth = parentDepth + 1
	return nil
}

// Complete marks the task as completed
func (t *Task) Complete() {
	now := time.Now()
	t.Status = models.StatusCompleted
	t.CompletedAt = &now
	t.UpdatedAt = now
}

// Uncomplete marks the task as pending again
func (t *Task) Uncomplete() {
	t.Status = models.StatusPending
	t.CompletedAt = nil
	t.UpdatedAt = time.Now()
}

// IncrementVersion increments the version for conflict detection
func (t *Task) IncrementVersion() {
	t.Version++
	t.UpdatedAt = time.Now()
}

// ErrMaxDepthExceeded is returned when trying to create a task too deep
var ErrMaxDepthExceeded = &TaskError{
	Code:    "MAX_DEPTH_EXCEEDED",
	Message: "Task depth cannot exceed 1 (maximum 2 layers). Consider promoting to a Project.",
}

// TaskError represents a task-specific error
type TaskError struct {
	Code    string
	Message string
}

func (e *TaskError) Error() string {
	return e.Message
}

// =====================================================
// Attachment Models
// =====================================================

// AttachmentType represents the type of attachment
type AttachmentType string

const (
	AttachmentTypeLink     AttachmentType = "link"
	AttachmentTypeDocument AttachmentType = "document"
	AttachmentTypeImage    AttachmentType = "image"
)

// Attachment represents a file or link attached to a task
type Attachment struct {
	ID           uuid.UUID      `json:"id" db:"id"`
	TaskID       uuid.UUID      `json:"task_id" db:"task_id"`
	UserID       uuid.UUID      `json:"user_id" db:"user_id"`
	Type         AttachmentType `json:"type" db:"type"`
	Name         string         `json:"name" db:"name"`
	URL          string         `json:"url" db:"url"`
	MimeType     *string        `json:"mime_type,omitempty" db:"mime_type"`
	SizeBytes    *int64         `json:"size_bytes,omitempty" db:"size_bytes"`
	ThumbnailURL *string        `json:"thumbnail_url,omitempty" db:"thumbnail_url"`
	Metadata     map[string]any `json:"metadata,omitempty" db:"metadata"`
	Data         []byte         `json:"-" db:"data"` // File content stored as BLOB (not serialized in JSON)
	CreatedAt    time.Time      `json:"created_at" db:"created_at"`
	DeletedAt    *time.Time     `json:"deleted_at,omitempty" db:"deleted_at"`
}

// NewAttachment creates a new attachment
func NewAttachment(taskID, userID uuid.UUID, attachType AttachmentType, name, url string) *Attachment {
	return &Attachment{
		ID:        uuid.New(),
		TaskID:    taskID,
		UserID:    userID,
		Type:      attachType,
		Name:      name,
		URL:       url,
		Metadata:  make(map[string]any),
		CreatedAt: time.Now(),
	}
}

// NewLinkAttachment creates a link attachment
func NewLinkAttachment(taskID, userID uuid.UUID, name, url string) *Attachment {
	return NewAttachment(taskID, userID, AttachmentTypeLink, name, url)
}

// NewFileAttachment creates a file attachment (document or image)
func NewFileAttachment(taskID, userID uuid.UUID, name, url, mimeType string, sizeBytes int64, isImage bool) *Attachment {
	attachType := AttachmentTypeDocument
	if isImage {
		attachType = AttachmentTypeImage
	}
	a := NewAttachment(taskID, userID, attachType, name, url)
	a.MimeType = &mimeType
	a.SizeBytes = &sizeBytes
	return a
}

// NewFileAttachmentWithData creates a file attachment with inline data storage
func NewFileAttachmentWithData(taskID, userID uuid.UUID, name, mimeType string, data []byte) *Attachment {
	isImage := strings.HasPrefix(mimeType, "image/")
	attachType := AttachmentTypeDocument
	if isImage {
		attachType = AttachmentTypeImage
	}

	sizeBytes := int64(len(data))
	return &Attachment{
		ID:        uuid.New(),
		TaskID:    taskID,
		UserID:    userID,
		Type:      attachType,
		Name:      name,
		URL:       "", // Will be set to download URL after creation
		MimeType:  &mimeType,
		SizeBytes: &sizeBytes,
		Data:      data,
		Metadata:  make(map[string]any),
		CreatedAt: time.Now(),
	}
}
