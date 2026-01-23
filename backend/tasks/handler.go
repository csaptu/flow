package tasks

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"strings"
	"time"

	"github.com/gofiber/fiber/v2"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/csaptu/flow/common/dto"
	commonModels "github.com/csaptu/flow/common/models"
	"github.com/csaptu/flow/pkg/httputil"
	"github.com/csaptu/flow/pkg/llm"
	"github.com/csaptu/flow/pkg/middleware"
	"github.com/csaptu/flow/tasks/models"
)

// TaskHandler handles task endpoints
type TaskHandler struct {
	db        *pgxpool.Pool
	llm       *llm.MultiClient
	aiService *AIService
}

// NewTaskHandler creates a new task handler
func NewTaskHandler(db *pgxpool.Pool, llmClient *llm.MultiClient) *TaskHandler {
	return &TaskHandler{
		db:        db,
		llm:       llmClient,
		aiService: NewAIService(db, llmClient),
	}
}

// CreateRequest represents the task creation request
type CreateRequest struct {
	ID          *string  `json:"id,omitempty"` // Client-provided ID for offline-first sync
	Title       string   `json:"title"`
	Description *string  `json:"description,omitempty"`
	DueAt       *string  `json:"due_at,omitempty"`       // Full timestamp: RFC3339 format
	HasDueTime  *bool    `json:"has_due_time,omitempty"` // true = specific time matters
	Priority    *int     `json:"priority,omitempty"`
	Tags        []string `json:"tags,omitempty"`
	ParentID    *string  `json:"parent_id,omitempty"`
}

// UpdateRequest represents the task update request
type UpdateRequest struct {
	Title       *string  `json:"title,omitempty"`
	Description *string  `json:"description,omitempty"`
	DueAt       *string  `json:"due_at,omitempty"`       // Full timestamp: RFC3339 format (empty string to clear)
	HasDueTime  *bool    `json:"has_due_time,omitempty"` // true = specific time matters
	ClearDueAt  *bool    `json:"clear_due_at,omitempty"` // true = clear due_at
	Priority    *int     `json:"priority,omitempty"`
	Status      *string  `json:"status,omitempty"`
	Tags        []string `json:"tags,omitempty"`
	ParentID    *string  `json:"parent_id,omitempty"` // Set to empty string to remove parent
}

// TaskResponse represents a task in API responses
type TaskResponse struct {
	ID                 string              `json:"id"`
	Title              string              `json:"title"`                            // User's original input
	Description        *string             `json:"description,omitempty"`            // User's original input
	AICleanedTitle     *string             `json:"ai_cleaned_title,omitempty"`       // AI cleaned version (null = not cleaned)
	AICleanedDesc      *string             `json:"ai_cleaned_description,omitempty"` // AI cleaned version (null = not cleaned)
	DisplayTitle       string              `json:"display_title"`                    // Computed: ai_cleaned_title ?? title
	DisplayDescription *string             `json:"display_description,omitempty"`    // Computed: ai_cleaned_description ?? description
	Status             string              `json:"status"`
	Priority           int                 `json:"priority"`
	DueAt              *string             `json:"due_at,omitempty"` // Full timestamp: RFC3339 format
	HasDueTime         bool                `json:"has_due_time"`     // true = specific time matters
	CompletedAt        *string             `json:"completed_at,omitempty"`
	Tags               []string            `json:"tags"`
	ParentID           *string             `json:"parent_id,omitempty"`
	Depth              int                 `json:"depth"`
	SortOrder          int                 `json:"sort_order"`
	Complexity         int                 `json:"complexity"`
	HasChildren        bool                `json:"has_children"`
	ChildrenCount      int                 `json:"children_count"`
	Entities           []models.TaskEntity `json:"entities"`
	DuplicateOf        []string            `json:"duplicate_of"`
	DuplicateResolved  bool                `json:"duplicate_resolved"`
	CreatedAt          string              `json:"created_at"`
	UpdatedAt          string              `json:"updated_at"`
}

// Create handles task creation
func (h *TaskHandler) Create(c *fiber.Ctx) error {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		return httputil.Unauthorized(c, "")
	}

	var req CreateRequest
	if err := c.BodyParser(&req); err != nil {
		return httputil.BadRequest(c, "invalid request body")
	}

	if req.Title == "" {
		return httputil.ValidationError(c, "validation failed", map[string]string{
			"title": "required",
		})
	}

	task := models.NewTask(userID, req.Title)

	// Use client-provided ID if present (for offline-first sync)
	if req.ID != nil {
		clientID, err := uuid.Parse(*req.ID)
		if err != nil {
			return httputil.BadRequest(c, "invalid client id format")
		}
		task.ID = clientID
	}

	task.Description = req.Description

	if req.DueAt != nil {
		// Parse RFC3339 timestamp
		dueAt, err := time.Parse(time.RFC3339, *req.DueAt)
		if err != nil {
			return httputil.BadRequest(c, "invalid due_at format, expected RFC3339 timestamp")
		}
		task.DueAt = &dueAt
		if req.HasDueTime != nil {
			task.HasDueTime = *req.HasDueTime
		}
	}

	if req.Priority != nil {
		task.Priority = commonModels.Priority(*req.Priority)
	}

	if req.Tags != nil {
		task.Tags = req.Tags
	}

	// Handle parent task
	if req.ParentID != nil {
		parentID, err := uuid.Parse(*req.ParentID)
		if err != nil {
			return httputil.BadRequest(c, "invalid parent_id")
		}

		// Get parent task to check depth
		var parentDepth int
		err = h.db.QueryRow(c.Context(),
			"SELECT depth FROM tasks WHERE id = $1 AND user_id = $2 AND deleted_at IS NULL",
			parentID, userID,
		).Scan(&parentDepth)
		if err == pgx.ErrNoRows {
			return httputil.NotFound(c, "parent task")
		}
		if err != nil {
			return httputil.InternalError(c, "database error")
		}

		if err := task.SetParent(parentID, parentDepth); err != nil {
			return httputil.BadRequest(c, err.Error())
		}
	}

	// Insert task
	entitiesJSON, _ := json.Marshal(task.Entities)

	_, err = h.db.Exec(c.Context(),
		`INSERT INTO tasks (id, user_id, title, description, status, priority, due_at, has_due_time, tags,
		 parent_id, depth, ai_entities, version, created_at, updated_at)
		 VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15)`,
		task.ID, task.UserID, task.Title, task.Description, task.Status, task.Priority,
		task.DueAt, task.HasDueTime, task.Tags, task.ParentID, task.Depth, entitiesJSON,
		task.Version, task.CreatedAt, task.UpdatedAt,
	)
	if err != nil {
		return httputil.InternalError(c, "failed to create task")
	}

	// Auto-process with AI (async, don't block response)
	go h.autoProcessTaskWithAI(c.Context(), userID, task)

	return httputil.Created(c, toTaskResponse(task, 0))
}

// GetByID handles getting a task by ID
func (h *TaskHandler) GetByID(c *fiber.Ctx) error {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		return httputil.Unauthorized(c, "")
	}

	taskID, err := uuid.Parse(c.Params("id"))
	if err != nil {
		return httputil.BadRequest(c, "invalid task ID")
	}

	task, childCount, err := h.getTask(c.Context(), taskID, userID)
	if err != nil {
		return err
	}

	return httputil.Success(c, toTaskResponse(task, childCount))
}

// List handles listing tasks with filters
// Returns all tasks including subtasks so the client can build the tree
func (h *TaskHandler) List(c *fiber.Ctx) error {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		return httputil.Unauthorized(c, "")
	}

	pagination := httputil.ParsePagination(c)

	// Get all tasks including subtasks (client filters by parent_id)
	rows, err := h.db.Query(c.Context(),
		`SELECT t.id, t.title, t.description, t.ai_cleaned_title, t.ai_cleaned_description,
		 t.status, t.priority, t.due_at, t.has_due_time, t.completed_at, t.tags,
		 t.parent_id, t.depth, t.sort_order, t.complexity, t.ai_entities, COALESCE(t.duplicate_of, '[]'), COALESCE(t.duplicate_resolved, false),
		 t.created_at, t.updated_at,
		 (SELECT COUNT(*) FROM tasks WHERE parent_id = t.id AND deleted_at IS NULL) as children_count
		 FROM tasks t
		 WHERE t.user_id = $1 AND t.deleted_at IS NULL
		 ORDER BY t.created_at DESC
		 LIMIT $2 OFFSET $3`,
		userID, pagination.PageSize, pagination.Offset(),
	)
	if err != nil {
		return httputil.InternalError(c, "database error")
	}
	defer rows.Close()

	tasks := make([]TaskResponse, 0)
	for rows.Next() {
		task, childCount, err := scanTask(rows)
		if err != nil {
			continue
		}
		tasks = append(tasks, toTaskResponse(task, childCount))
	}

	// Get total count (all tasks including subtasks)
	var totalCount int64
	_ = h.db.QueryRow(c.Context(),
		"SELECT COUNT(*) FROM tasks WHERE user_id = $1 AND deleted_at IS NULL",
		userID,
	).Scan(&totalCount)

	return httputil.SuccessWithMeta(c, tasks, httputil.BuildMeta(pagination.Page, pagination.PageSize, totalCount))
}

// Today handles listing tasks due today
func (h *TaskHandler) Today(c *fiber.Ctx) error {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		return httputil.Unauthorized(c, "")
	}

	today := time.Now().Truncate(24 * time.Hour)
	tomorrow := today.Add(24 * time.Hour)

	rows, err := h.db.Query(c.Context(),
		`SELECT t.id, t.title, t.description, t.ai_cleaned_title, t.ai_cleaned_description,
		 t.status, t.priority, t.due_at, t.has_due_time, t.completed_at, t.tags,
		 t.parent_id, t.depth, t.sort_order, t.complexity, t.ai_entities, COALESCE(t.duplicate_of, '[]'), COALESCE(t.duplicate_resolved, false),
		 t.created_at, t.updated_at,
		 (SELECT COUNT(*) FROM tasks WHERE parent_id = t.id AND deleted_at IS NULL) as children_count
		 FROM tasks t
		 WHERE t.user_id = $1 AND t.deleted_at IS NULL
		 AND t.due_at >= $2 AND t.due_at < $3
		 AND t.status != 'completed'
		 ORDER BY t.priority DESC, t.due_at ASC`,
		userID, today, tomorrow,
	)
	if err != nil {
		return httputil.InternalError(c, "database error")
	}
	defer rows.Close()

	tasks := make([]TaskResponse, 0)
	for rows.Next() {
		task, childCount, err := scanTask(rows)
		if err != nil {
			continue
		}
		tasks = append(tasks, toTaskResponse(task, childCount))
	}

	return httputil.Success(c, tasks)
}

// Inbox handles listing tasks without due date
func (h *TaskHandler) Inbox(c *fiber.Ctx) error {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		return httputil.Unauthorized(c, "")
	}

	rows, err := h.db.Query(c.Context(),
		`SELECT t.id, t.title, t.description, t.ai_cleaned_title, t.ai_cleaned_description,
		 t.status, t.priority, t.due_at, t.has_due_time, t.completed_at, t.tags,
		 t.parent_id, t.depth, t.sort_order, t.complexity, t.ai_entities, COALESCE(t.duplicate_of, '[]'), COALESCE(t.duplicate_resolved, false),
		 t.created_at, t.updated_at,
		 (SELECT COUNT(*) FROM tasks WHERE parent_id = t.id AND deleted_at IS NULL) as children_count
		 FROM tasks t
		 WHERE t.user_id = $1 AND t.deleted_at IS NULL
		 AND t.due_at IS NULL AND t.status != 'completed'
		 ORDER BY t.created_at DESC`,
		userID,
	)
	if err != nil {
		return httputil.InternalError(c, "database error")
	}
	defer rows.Close()

	tasks := make([]TaskResponse, 0)
	for rows.Next() {
		task, childCount, err := scanTask(rows)
		if err != nil {
			continue
		}
		tasks = append(tasks, toTaskResponse(task, childCount))
	}

	return httputil.Success(c, tasks)
}

// Upcoming handles listing upcoming tasks
func (h *TaskHandler) Upcoming(c *fiber.Ctx) error {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		return httputil.Unauthorized(c, "")
	}

	tomorrow := time.Now().Truncate(24*time.Hour).Add(24 * time.Hour)

	rows, err := h.db.Query(c.Context(),
		`SELECT t.id, t.title, t.description, t.ai_cleaned_title, t.ai_cleaned_description,
		 t.status, t.priority, t.due_at, t.has_due_time, t.completed_at, t.tags,
		 t.parent_id, t.depth, t.sort_order, t.complexity, t.ai_entities, COALESCE(t.duplicate_of, '[]'), COALESCE(t.duplicate_resolved, false),
		 t.created_at, t.updated_at,
		 (SELECT COUNT(*) FROM tasks WHERE parent_id = t.id AND deleted_at IS NULL) as children_count
		 FROM tasks t
		 WHERE t.user_id = $1 AND t.deleted_at IS NULL
		 AND t.due_at >= $2 AND t.status != 'completed'
		 ORDER BY t.due_at ASC
		 LIMIT 100`,
		userID, tomorrow,
	)
	if err != nil {
		return httputil.InternalError(c, "database error")
	}
	defer rows.Close()

	tasks := make([]TaskResponse, 0)
	for rows.Next() {
		task, childCount, err := scanTask(rows)
		if err != nil {
			continue
		}
		tasks = append(tasks, toTaskResponse(task, childCount))
	}

	return httputil.Success(c, tasks)
}

// Completed handles listing completed tasks
func (h *TaskHandler) Completed(c *fiber.Ctx) error {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		return httputil.Unauthorized(c, "")
	}

	pagination := httputil.ParsePagination(c)

	rows, err := h.db.Query(c.Context(),
		`SELECT t.id, t.title, t.description, t.ai_cleaned_title, t.ai_cleaned_description,
		 t.status, t.priority, t.due_at, t.has_due_time, t.completed_at, t.tags,
		 t.parent_id, t.depth, t.sort_order, t.complexity, t.ai_entities, COALESCE(t.duplicate_of, '[]'), COALESCE(t.duplicate_resolved, false),
		 t.created_at, t.updated_at,
		 (SELECT COUNT(*) FROM tasks WHERE parent_id = t.id AND deleted_at IS NULL) as children_count
		 FROM tasks t
		 WHERE t.user_id = $1 AND t.deleted_at IS NULL AND t.status = 'completed'
		 ORDER BY t.completed_at DESC
		 LIMIT $2 OFFSET $3`,
		userID, pagination.PageSize, pagination.Offset(),
	)
	if err != nil {
		return httputil.InternalError(c, "database error")
	}
	defer rows.Close()

	tasks := make([]TaskResponse, 0)
	for rows.Next() {
		task, childCount, err := scanTask(rows)
		if err != nil {
			continue
		}
		tasks = append(tasks, toTaskResponse(task, childCount))
	}

	return httputil.Success(c, tasks)
}

// Update handles updating a task
func (h *TaskHandler) Update(c *fiber.Ctx) error {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		return httputil.Unauthorized(c, "")
	}

	taskID, err := uuid.Parse(c.Params("id"))
	if err != nil {
		return httputil.BadRequest(c, "invalid task ID")
	}

	var req UpdateRequest
	if err := c.BodyParser(&req); err != nil {
		return httputil.BadRequest(c, "invalid request body")
	}

	// Get existing task
	task, childCount, err := h.getTask(c.Context(), taskID, userID)
	if err != nil {
		return err
	}

	// Apply updates with smart AI field preservation:
	// Only clear AI-cleaned fields if the user actually changed to something new
	// (not same as original, not same as AI-cleaned version)
	if req.Title != nil {
		newTitle := *req.Title
		isSameAsOriginal := newTitle == task.Title
		isSameAsAiCleaned := task.AICleanedTitle != nil && newTitle == *task.AICleanedTitle

		task.Title = newTitle
		// Only clear AI cleaned title if user changed to something genuinely new
		if !isSameAsOriginal && !isSameAsAiCleaned {
			task.AICleanedTitle = nil
		}
	}
	if req.Description != nil {
		newDesc := ""
		if req.Description != nil {
			newDesc = *req.Description
		}
		oldDesc := ""
		if task.Description != nil {
			oldDesc = *task.Description
		}
		isSameAsOriginal := newDesc == oldDesc
		isSameAsAiCleaned := task.AICleanedDescription != nil && newDesc == *task.AICleanedDescription

		task.Description = req.Description
		// Only clear AI cleaned description if user changed to something genuinely new
		if !isSameAsOriginal && !isSameAsAiCleaned {
			task.AICleanedDescription = nil
		}
	}
	// Handle clearing due_at
	if req.ClearDueAt != nil && *req.ClearDueAt {
		task.DueAt = nil
		task.HasDueTime = false
	} else if req.DueAt != nil {
		// Parse RFC3339 timestamp
		dueAt, err := time.Parse(time.RFC3339, *req.DueAt)
		if err != nil {
			return httputil.BadRequest(c, "invalid due_at format, expected RFC3339 timestamp")
		}
		task.DueAt = &dueAt
		if req.HasDueTime != nil {
			task.HasDueTime = *req.HasDueTime
		}
	} else if req.HasDueTime != nil {
		// Update just the has_due_time flag without changing due_at
		task.HasDueTime = *req.HasDueTime
	}
	if req.Priority != nil {
		task.Priority = commonModels.Priority(*req.Priority)
	}
	if req.Status != nil {
		task.Status = commonModels.Status(*req.Status)
		if task.Status == commonModels.StatusCompleted && task.CompletedAt == nil {
			now := time.Now()
			task.CompletedAt = &now
		}
	}
	if req.Tags != nil {
		task.Tags = req.Tags
	}

	// Handle parent_id update (for making a task a subtask of another)
	if req.ParentID != nil {
		if *req.ParentID == "" {
			// Remove parent - make it a root task
			task.ParentID = nil
			task.Depth = 0
		} else {
			// Set new parent
			parentID, err := uuid.Parse(*req.ParentID)
			if err != nil {
				return httputil.BadRequest(c, "invalid parent_id")
			}

			// Prevent setting self as parent
			if parentID == taskID {
				return httputil.BadRequest(c, "task cannot be its own parent")
			}

			// Get parent task to check depth
			var parentDepth int
			err = h.db.QueryRow(c.Context(),
				"SELECT depth FROM tasks WHERE id = $1 AND user_id = $2 AND deleted_at IS NULL",
				parentID, userID,
			).Scan(&parentDepth)
			if err == pgx.ErrNoRows {
				return httputil.NotFound(c, "parent task")
			}
			if err != nil {
				return httputil.InternalError(c, "database error")
			}

			// Enforce 2-layer limit
			if parentDepth >= 1 {
				return httputil.BadRequest(c, "maximum nesting depth exceeded (max 2 layers)")
			}

			// Check if this task has children - if so, it can't become a subtask
			if childCount > 0 {
				return httputil.BadRequest(c, "task with subtasks cannot become a subtask")
			}

			task.ParentID = &parentID
			task.Depth = parentDepth + 1
		}
	}

	task.IncrementVersion()

	// Update task
	_, err = h.db.Exec(c.Context(),
		`UPDATE tasks SET title = $1, description = $2, due_at = $3, has_due_time = $4, priority = $5,
		 status = $6, completed_at = $7, tags = $8, parent_id = $9, depth = $10,
		 ai_cleaned_title = $11, ai_cleaned_description = $12, version = $13, updated_at = $14
		 WHERE id = $15 AND user_id = $16`,
		task.Title, task.Description, task.DueAt, task.HasDueTime, task.Priority, task.Status,
		task.CompletedAt, task.Tags, task.ParentID, task.Depth, task.AICleanedTitle, task.AICleanedDescription,
		task.Version, task.UpdatedAt,
		taskID, userID,
	)
	if err != nil {
		return httputil.InternalError(c, "failed to update task")
	}

	// Note: Don't auto-process with AI on updates - only on create.
	// User edits should not trigger auto-cleanup. AI features are manual-only
	// after initial task creation (clean button, extract button, etc.)

	return httputil.Success(c, toTaskResponse(task, childCount))
}

// Delete handles deleting a task
func (h *TaskHandler) Delete(c *fiber.Ctx) error {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		return httputil.Unauthorized(c, "")
	}

	taskID, err := uuid.Parse(c.Params("id"))
	if err != nil {
		return httputil.BadRequest(c, "invalid task ID")
	}

	// Soft delete task and children
	now := time.Now()
	_, err = h.db.Exec(c.Context(),
		`UPDATE tasks SET deleted_at = $1 WHERE (id = $2 OR parent_id = $2) AND user_id = $3`,
		now, taskID, userID,
	)
	if err != nil {
		return httputil.InternalError(c, "failed to delete task")
	}

	return httputil.NoContent(c)
}

// Complete marks a task as completed
func (h *TaskHandler) Complete(c *fiber.Ctx) error {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		return httputil.Unauthorized(c, "")
	}

	taskID, err := uuid.Parse(c.Params("id"))
	if err != nil {
		return httputil.BadRequest(c, "invalid task ID")
	}

	now := time.Now()
	result, err := h.db.Exec(c.Context(),
		`UPDATE tasks SET status = 'completed', completed_at = $1, version = version + 1, updated_at = $1
		 WHERE id = $2 AND user_id = $3 AND deleted_at IS NULL`,
		now, taskID, userID,
	)
	if err != nil {
		return httputil.InternalError(c, "failed to complete task")
	}

	if result.RowsAffected() == 0 {
		return httputil.NotFound(c, "task")
	}

	task, childCount, _ := h.getTask(c.Context(), taskID, userID)
	return httputil.Success(c, toTaskResponse(task, childCount))
}

// Uncomplete marks a task as pending
func (h *TaskHandler) Uncomplete(c *fiber.Ctx) error {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		return httputil.Unauthorized(c, "")
	}

	taskID, err := uuid.Parse(c.Params("id"))
	if err != nil {
		return httputil.BadRequest(c, "invalid task ID")
	}

	now := time.Now()
	result, err := h.db.Exec(c.Context(),
		`UPDATE tasks SET status = 'pending', completed_at = NULL, version = version + 1, updated_at = $1
		 WHERE id = $2 AND user_id = $3 AND deleted_at IS NULL`,
		now, taskID, userID,
	)
	if err != nil {
		return httputil.InternalError(c, "failed to uncomplete task")
	}

	if result.RowsAffected() == 0 {
		return httputil.NotFound(c, "task")
	}

	task, childCount, _ := h.getTask(c.Context(), taskID, userID)
	return httputil.Success(c, toTaskResponse(task, childCount))
}

// CreateChild creates a child task
func (h *TaskHandler) CreateChild(c *fiber.Ctx) error {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		return httputil.Unauthorized(c, "")
	}

	parentID, err := uuid.Parse(c.Params("id"))
	if err != nil {
		return httputil.BadRequest(c, "invalid parent ID")
	}

	var req CreateRequest
	if err := c.BodyParser(&req); err != nil {
		return httputil.BadRequest(c, "invalid request body")
	}

	// Get parent task
	var parentDepth int
	err = h.db.QueryRow(c.Context(),
		"SELECT depth FROM tasks WHERE id = $1 AND user_id = $2 AND deleted_at IS NULL",
		parentID, userID,
	).Scan(&parentDepth)
	if err == pgx.ErrNoRows {
		return httputil.NotFound(c, "parent task")
	}
	if err != nil {
		return httputil.InternalError(c, "database error")
	}

	// Check depth limit
	if parentDepth >= 1 {
		return httputil.BadRequest(c, "maximum task depth exceeded (2 layers max)")
	}

	// Get max sort_order of existing children
	var maxSortOrder int
	err = h.db.QueryRow(c.Context(),
		`SELECT COALESCE(MAX(sort_order), -1) FROM tasks WHERE parent_id = $1 AND user_id = $2 AND deleted_at IS NULL`,
		parentID, userID,
	).Scan(&maxSortOrder)
	if err != nil {
		maxSortOrder = -1
	}

	task := models.NewTask(userID, req.Title)
	task.Description = req.Description
	task.ParentID = &parentID
	task.Depth = parentDepth + 1
	task.SortOrder = maxSortOrder + 1

	if req.Priority != nil {
		task.Priority = commonModels.Priority(*req.Priority)
	}

	entitiesJSON, _ := json.Marshal(task.Entities)

	_, err = h.db.Exec(c.Context(),
		`INSERT INTO tasks (id, user_id, title, description, status, priority, due_at, has_due_time, tags,
		 parent_id, depth, sort_order, ai_entities, version, created_at, updated_at)
		 VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16)`,
		task.ID, task.UserID, task.Title, task.Description, task.Status, task.Priority,
		task.DueAt, task.HasDueTime, task.Tags, task.ParentID, task.Depth, task.SortOrder, entitiesJSON,
		task.Version, task.CreatedAt, task.UpdatedAt,
	)
	if err != nil {
		return httputil.InternalError(c, "failed to create task")
	}

	return httputil.Created(c, toTaskResponse(task, 0))
}

// GetChildren gets child tasks
func (h *TaskHandler) GetChildren(c *fiber.Ctx) error {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		return httputil.Unauthorized(c, "")
	}

	parentID, err := uuid.Parse(c.Params("id"))
	if err != nil {
		return httputil.BadRequest(c, "invalid parent ID")
	}

	rows, err := h.db.Query(c.Context(),
		`SELECT t.id, t.title, t.description, t.ai_cleaned_title, t.ai_cleaned_description,
		 t.status, t.priority, t.due_at, t.has_due_time, t.completed_at, t.tags,
		 t.parent_id, t.depth, t.sort_order, t.complexity, t.ai_entities, COALESCE(t.duplicate_of, '[]'), COALESCE(t.duplicate_resolved, false),
		 t.created_at, t.updated_at,
		 0 as children_count
		 FROM tasks t
		 WHERE t.user_id = $1 AND t.parent_id = $2 AND t.deleted_at IS NULL
		 ORDER BY t.sort_order ASC, t.created_at ASC`,
		userID, parentID,
	)
	if err != nil {
		return httputil.InternalError(c, "database error")
	}
	defer rows.Close()

	tasks := make([]TaskResponse, 0)
	for rows.Next() {
		task, childCount, err := scanTask(rows)
		if err != nil {
			continue
		}
		tasks = append(tasks, toTaskResponse(task, childCount))
	}

	return httputil.Success(c, tasks)
}

// ReorderRequest is the request body for reordering subtasks
type ReorderRequest struct {
	TaskIDs []string `json:"task_ids"` // Ordered list of subtask IDs
}

// ReorderChildren reorders subtasks within a parent task
func (h *TaskHandler) ReorderChildren(c *fiber.Ctx) error {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		return httputil.Unauthorized(c, "")
	}

	parentID, err := uuid.Parse(c.Params("id"))
	if err != nil {
		return httputil.BadRequest(c, "invalid parent ID")
	}

	var req ReorderRequest
	if err := c.BodyParser(&req); err != nil {
		return httputil.BadRequest(c, "invalid request body")
	}

	if len(req.TaskIDs) == 0 {
		return httputil.BadRequest(c, "task_ids is required")
	}

	// Verify parent task exists and belongs to user
	var exists bool
	err = h.db.QueryRow(c.Context(),
		`SELECT EXISTS(SELECT 1 FROM tasks WHERE id = $1 AND user_id = $2 AND deleted_at IS NULL)`,
		parentID, userID,
	).Scan(&exists)
	if err != nil || !exists {
		return httputil.NotFound(c, "parent task")
	}

	// Update sort_order for each task in the new order
	for i, taskIDStr := range req.TaskIDs {
		taskID, err := uuid.Parse(taskIDStr)
		if err != nil {
			continue
		}

		_, err = h.db.Exec(c.Context(),
			`UPDATE tasks SET sort_order = $1, updated_at = NOW()
			 WHERE id = $2 AND parent_id = $3 AND user_id = $4 AND deleted_at IS NULL`,
			i, taskID, parentID, userID,
		)
		if err != nil {
			// Log but continue with other updates
			continue
		}
	}

	return httputil.Success(c, map[string]string{"status": "ok"})
}

// AIDecompose uses AI to break down a task into subtasks
func (h *TaskHandler) AIDecompose(c *fiber.Ctx) error {
	if h.llm == nil {
		return httputil.ServiceUnavailable(c, "AI service not available")
	}

	userID, err := middleware.GetUserID(c)
	if err != nil {
		return httputil.Unauthorized(c, "")
	}

	taskID, err := uuid.Parse(c.Params("id"))
	if err != nil {
		return httputil.BadRequest(c, "invalid task ID")
	}

	task, childCount, err := h.getTask(c.Context(), taskID, userID)
	if err != nil {
		return err
	}

	// Check if task can have children (only root tasks can)
	if task.Depth > 0 {
		return httputil.BadRequest(c, "subtasks cannot be further decomposed")
	}

	// Call LLM to decompose task into subtasks
	prompt := fmt.Sprintf(`Break down this task into 2-5 actionable subtasks.
Task: %s
%s

Return ONLY a JSON array of subtask titles, like:
["First subtask title", "Second subtask title", "Third subtask title"]

Each subtask should be:
- A single, concrete action
- In logical order
- Starting with an action verb`, task.Title, func() string {
		if task.Description != nil {
			return "Description: " + *task.Description
		}
		return ""
	}())

	resp, err := h.llm.Complete(c.Context(), llm.CompletionRequest{
		Messages: []llm.Message{
			{Role: "user", Content: prompt},
		},
		MaxTokens:   500,
		Temperature: 0.3,
	})
	if err != nil {
		return httputil.ServiceUnavailable(c, "AI service error")
	}

	// Parse AI response - expecting array of strings
	var subtaskTitles []string
	content := strings.TrimSpace(resp.Content)
	// Handle markdown code blocks
	if strings.HasPrefix(content, "```") {
		lines := strings.Split(content, "\n")
		var jsonLines []string
		inBlock := false
		for _, line := range lines {
			if strings.HasPrefix(line, "```") {
				inBlock = !inBlock
				continue
			}
			if inBlock {
				jsonLines = append(jsonLines, line)
			}
		}
		content = strings.Join(jsonLines, "\n")
	}

	if err := json.Unmarshal([]byte(content), &subtaskTitles); err != nil {
		return httputil.InternalError(c, "failed to parse AI response")
	}

	// Create subtasks as real child tasks
	now := time.Now()
	createdCount := 0
	for _, title := range subtaskTitles {
		title = strings.TrimSpace(title)
		if title == "" {
			continue
		}

		subtask := models.NewTask(userID, title)
		subtask.ParentID = &taskID
		subtask.Depth = 1
		subtask.CreatedAt = now.Add(time.Duration(createdCount) * time.Millisecond) // Ensure ordering
		subtask.UpdatedAt = now

		_, err = h.db.Exec(c.Context(),
			`INSERT INTO tasks (id, user_id, title, status, priority, tags, parent_id, depth, ai_entities, version, created_at, updated_at)
			 VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)`,
			subtask.ID, subtask.UserID, subtask.Title, subtask.Status, subtask.Priority,
			subtask.Tags, subtask.ParentID, subtask.Depth, []byte("[]"),
			subtask.Version, subtask.CreatedAt, subtask.UpdatedAt,
		)
		if err != nil {
			continue // Skip failed inserts
		}
		createdCount++
	}

	// Return updated parent task with new children count
	return httputil.Success(c, toTaskResponse(task, childCount+createdCount))
}

// AIClean uses AI to clean up a task title and description
func (h *TaskHandler) AIClean(c *fiber.Ctx) error {
	if h.llm == nil {
		return httputil.ServiceUnavailable(c, "AI service not available")
	}

	userID, err := middleware.GetUserID(c)
	if err != nil {
		return httputil.Unauthorized(c, "")
	}

	taskID, err := uuid.Parse(c.Params("id"))
	if err != nil {
		return httputil.BadRequest(c, "invalid task ID")
	}

	task, childCount, err := h.getTask(c.Context(), taskID, userID)
	if err != nil {
		return err
	}

	// Call LLM to clean up task
	prompt := fmt.Sprintf(`Clean up this task to be clearer and more concise.
Original: %s
%s

Return ONLY a JSON object:
{"title": "Cleaned title (max 8 words)", "summary": "Brief summary if needed (max 15 words)"}`,
		task.Title, func() string {
		if task.Description != nil {
			return "Description: " + *task.Description
		}
		return ""
	}())

	resp, err := h.llm.Complete(c.Context(), llm.CompletionRequest{
		Messages: []llm.Message{
			{Role: "user", Content: prompt},
		},
		MaxTokens:   200,
		Temperature: 0.3,
	})
	if err != nil {
		return httputil.ServiceUnavailable(c, "AI service error")
	}

	// Parse AI response
	var cleaned struct {
		Title   string `json:"title"`
		Summary string `json:"summary"`
	}
	if err := json.Unmarshal([]byte(resp.Content), &cleaned); err != nil {
		return httputil.InternalError(c, "failed to parse AI response")
	}

	// Store AI cleaned version (don't modify original title)
	// ai_cleaned_title stores the cleaned text, title remains as user input
	task.AICleanedTitle = &cleaned.Title
	task.IncrementVersion()

	_, err = h.db.Exec(c.Context(),
		`UPDATE tasks SET ai_cleaned_title = $1, version = $2, updated_at = $3
		 WHERE id = $4 AND user_id = $5`,
		task.AICleanedTitle, task.Version, task.UpdatedAt, taskID, userID,
	)
	if err != nil {
		return httputil.InternalError(c, "failed to update task")
	}

	return httputil.Success(c, toTaskResponse(task, childCount))
}

// AIRate rates the complexity of a task (1-10 scale)
func (h *TaskHandler) AIRate(c *fiber.Ctx) error {
	if h.llm == nil {
		return httputil.ServiceUnavailable(c, "AI service not available")
	}

	userID, err := middleware.GetUserID(c)
	if err != nil {
		return httputil.Unauthorized(c, "")
	}

	taskID, err := uuid.Parse(c.Params("id"))
	if err != nil {
		return httputil.BadRequest(c, "invalid task ID")
	}

	task, childCount, err := h.getTask(c.Context(), taskID, userID)
	if err != nil {
		return err
	}

	// Check feature access
	if h.aiService != nil {
		canUse, _ := h.aiService.CheckAndIncrementUsage(c.Context(), userID, FeatureComplexity)
		if !canUse {
			return httputil.PaymentRequired(c, "Upgrade to Light tier for complexity rating")
		}
	}

	prompt := fmt.Sprintf(`Rate the complexity of this task on a scale of 1-10.

Task: %s
%s

Rating scale:
1-2: Trivial (e.g., "buy milk", "send text")
3-4: Simple (e.g., "schedule meeting", "write short email")
5-6: Moderate (e.g., "prepare presentation", "review document")
7-8: Complex (e.g., "design feature", "plan event")
9-10: Very complex (e.g., "launch product", "migrate system")

Return ONLY a JSON object:
{"complexity": <number 1-10>, "reason": "Brief explanation (max 15 words)"}`,
		task.Title, func() string {
			if task.Description != nil {
				return "Description: " + *task.Description
			}
			return ""
		}())

	resp, err := h.llm.Complete(c.Context(), llm.CompletionRequest{
		Messages: []llm.Message{
			{Role: "user", Content: prompt},
		},
		MaxTokens:   100,
		Temperature: 0.3,
	})
	if err != nil {
		return httputil.ServiceUnavailable(c, "AI service error")
	}

	var rated struct {
		Complexity int    `json:"complexity"`
		Reason     string `json:"reason"`
	}
	if err := json.Unmarshal([]byte(resp.Content), &rated); err != nil {
		return httputil.InternalError(c, "failed to parse AI response")
	}

	// Update task with complexity
	task.Complexity = rated.Complexity
	task.IncrementVersion()

	_, err = h.db.Exec(c.Context(),
		`UPDATE tasks SET complexity = $1, version = $2, updated_at = $3
		 WHERE id = $4 AND user_id = $5`,
		task.Complexity, task.Version, task.UpdatedAt, taskID, userID,
	)
	if err != nil {
		return httputil.InternalError(c, "failed to update task")
	}

	return httputil.Success(c, map[string]interface{}{
		"task":       toTaskResponse(task, childCount),
		"complexity": rated.Complexity,
		"reason":     rated.Reason,
	})
}

// AIExtract extracts entities (people, places, dates) from a task
func (h *TaskHandler) AIExtract(c *fiber.Ctx) error {
	if h.llm == nil {
		return httputil.ServiceUnavailable(c, "AI service not available")
	}

	userID, err := middleware.GetUserID(c)
	if err != nil {
		return httputil.Unauthorized(c, "")
	}

	taskID, err := uuid.Parse(c.Params("id"))
	if err != nil {
		return httputil.BadRequest(c, "invalid task ID")
	}

	task, childCount, err := h.getTask(c.Context(), taskID, userID)
	if err != nil {
		return err
	}

	// Check feature access
	if h.aiService != nil {
		canUse, _ := h.aiService.CheckAndIncrementUsage(c.Context(), userID, FeatureEntityExtraction)
		if !canUse {
			return httputil.PaymentRequired(c, "Upgrade to Light tier for entity extraction")
		}
	}

	prompt := fmt.Sprintf(`Extract key entities from this task.

Task: %s
%s

Return ONLY a JSON object:
{
  "entities": [
    {"type": "person", "value": "name"},
    {"type": "date", "value": "parsed date"},
    {"type": "location", "value": "place"},
    {"type": "organization", "value": "company name"},
    {"type": "email", "value": "email@example.com"},
    {"type": "phone", "value": "+1234567890"}
  ]
}

Only include entities that are actually present. Leave array empty if none found.`,
		task.Title, func() string {
			if task.Description != nil {
				return "Description: " + *task.Description
			}
			return ""
		}())

	resp, err := h.llm.Complete(c.Context(), llm.CompletionRequest{
		Messages: []llm.Message{
			{Role: "user", Content: prompt},
		},
		MaxTokens:   300,
		Temperature: 0.2,
	})
	if err != nil {
		return httputil.ServiceUnavailable(c, "AI service error")
	}

	var extracted struct {
		Entities []Entity `json:"entities"`
	}
	if err := json.Unmarshal([]byte(resp.Content), &extracted); err != nil {
		return httputil.InternalError(c, "failed to parse AI response")
	}

	// Store entities as JSON in task
	entitiesJSON, _ := json.Marshal(extracted.Entities)
	task.IncrementVersion()

	_, err = h.db.Exec(c.Context(),
		`UPDATE tasks SET ai_entities = $1, version = $2, updated_at = $3
		 WHERE id = $4 AND user_id = $5`,
		entitiesJSON, task.Version, task.UpdatedAt, taskID, userID,
	)
	if err != nil {
		return httputil.InternalError(c, "failed to update task")
	}

	return httputil.Success(c, map[string]interface{}{
		"task":     toTaskResponse(task, childCount),
		"entities": extracted.Entities,
	})
}

// AIRemind suggests a reminder time for a task
func (h *TaskHandler) AIRemind(c *fiber.Ctx) error {
	if h.llm == nil {
		return httputil.ServiceUnavailable(c, "AI service not available")
	}

	userID, err := middleware.GetUserID(c)
	if err != nil {
		return httputil.Unauthorized(c, "")
	}

	taskID, err := uuid.Parse(c.Params("id"))
	if err != nil {
		return httputil.BadRequest(c, "invalid task ID")
	}

	task, childCount, err := h.getTask(c.Context(), taskID, userID)
	if err != nil {
		return err
	}

	// Check feature access
	if h.aiService != nil {
		canUse, _ := h.aiService.CheckAndIncrementUsage(c.Context(), userID, FeatureReminder)
		if !canUse {
			return httputil.PaymentRequired(c, "Upgrade to Premium tier for smart reminders")
		}
	}

	now := time.Now()
	dueInfo := ""
	if task.DueAt != nil {
		dueInfo = fmt.Sprintf("Due date: %s", task.DueAt.Format("2006-01-02 15:04"))
	}

	prompt := fmt.Sprintf(`Suggest an appropriate reminder time for this task.

Task: %s
%s
%s
Current time: %s

Return ONLY a JSON object:
{"reminder_time": "ISO 8601 datetime", "reason": "Brief explanation (max 15 words)"}

Guidelines:
- Suggest time that gives enough prep time before any deadlines
- Consider task complexity and urgency
- Default to morning (9 AM) for general tasks
- For meetings, suggest 1 day before and 1 hour before`,
		task.Title, func() string {
			if task.Description != nil {
				return "Description: " + *task.Description
			}
			return ""
		}(), dueInfo, now.Format(time.RFC3339))

	resp, err := h.llm.Complete(c.Context(), llm.CompletionRequest{
		Messages: []llm.Message{
			{Role: "user", Content: prompt},
		},
		MaxTokens:   150,
		Temperature: 0.3,
	})
	if err != nil {
		return httputil.ServiceUnavailable(c, "AI service error")
	}

	var suggested struct {
		ReminderTime string `json:"reminder_time"`
		Reason       string `json:"reason"`
	}
	if err := json.Unmarshal([]byte(resp.Content), &suggested); err != nil {
		return httputil.InternalError(c, "failed to parse AI response")
	}

	// Parse and validate reminder time
	reminderTime, err := time.Parse(time.RFC3339, suggested.ReminderTime)
	if err != nil {
		// Try alternate format
		reminderTime, err = time.Parse("2006-01-02T15:04:05", suggested.ReminderTime)
		if err != nil {
			return httputil.InternalError(c, "invalid reminder time from AI")
		}
	}

	// Update task with reminder
	task.ReminderAt = &reminderTime
	task.IncrementVersion()

	_, err = h.db.Exec(c.Context(),
		`UPDATE tasks SET reminder_at = $1, version = $2, updated_at = $3
		 WHERE id = $4 AND user_id = $5`,
		task.ReminderAt, task.Version, task.UpdatedAt, taskID, userID,
	)
	if err != nil {
		return httputil.InternalError(c, "failed to update task")
	}

	return httputil.Success(c, map[string]interface{}{
		"task":          toTaskResponse(task, childCount),
		"reminder_time": reminderTime,
		"reason":        suggested.Reason,
	})
}

// AIEmail drafts an email based on the task
func (h *TaskHandler) AIEmail(c *fiber.Ctx) error {
	if h.llm == nil {
		return httputil.ServiceUnavailable(c, "AI service not available")
	}

	userID, err := middleware.GetUserID(c)
	if err != nil {
		return httputil.Unauthorized(c, "")
	}

	taskID, err := uuid.Parse(c.Params("id"))
	if err != nil {
		return httputil.BadRequest(c, "invalid task ID")
	}

	task, _, err := h.getTask(c.Context(), taskID, userID)
	if err != nil {
		return err
	}

	// Check feature access
	if h.aiService != nil {
		canUse, _ := h.aiService.CheckAndIncrementUsage(c.Context(), userID, FeatureDraftEmail)
		if !canUse {
			return httputil.PaymentRequired(c, "Upgrade to Premium tier for email drafts")
		}
	}

	prompt := fmt.Sprintf(`Draft a professional email based on this task.

Task: %s
%s

Return ONLY a JSON object:
{
  "to": "recipient if mentioned, otherwise leave empty",
  "subject": "Clear, concise email subject",
  "body": "Professional email body. Be concise but complete. Include greeting and sign-off placeholder."
}`,
		task.Title, func() string {
			if task.Description != nil {
				return "Description: " + *task.Description
			}
			return ""
		}())

	resp, err := h.llm.Complete(c.Context(), llm.CompletionRequest{
		Messages: []llm.Message{
			{Role: "user", Content: prompt},
		},
		MaxTokens:   500,
		Temperature: 0.4,
	})
	if err != nil {
		return httputil.ServiceUnavailable(c, "AI service error")
	}

	var draft DraftContent
	if err := json.Unmarshal([]byte(resp.Content), &draft); err != nil {
		return httputil.InternalError(c, "failed to parse AI response")
	}
	draft.Type = "email"

	// Save draft
	var draftID uuid.UUID
	if h.aiService != nil {
		draftID, _ = h.aiService.SaveDraft(c.Context(), userID, taskID, &draft)
	}

	return httputil.Success(c, map[string]interface{}{
		"draft_id": draftID,
		"draft":    draft,
	})
}

// AIInvite drafts a calendar invite based on the task
func (h *TaskHandler) AIInvite(c *fiber.Ctx) error {
	if h.llm == nil {
		return httputil.ServiceUnavailable(c, "AI service not available")
	}

	userID, err := middleware.GetUserID(c)
	if err != nil {
		return httputil.Unauthorized(c, "")
	}

	taskID, err := uuid.Parse(c.Params("id"))
	if err != nil {
		return httputil.BadRequest(c, "invalid task ID")
	}

	task, _, err := h.getTask(c.Context(), taskID, userID)
	if err != nil {
		return err
	}

	// Check feature access
	if h.aiService != nil {
		canUse, _ := h.aiService.CheckAndIncrementUsage(c.Context(), userID, FeatureDraftCalendar)
		if !canUse {
			return httputil.PaymentRequired(c, "Upgrade to Premium tier for calendar invites")
		}
	}

	now := time.Now()
	dueInfo := ""
	if task.DueAt != nil {
		dueInfo = fmt.Sprintf("Due/scheduled: %s", task.DueAt.Format("2006-01-02 15:04"))
	}

	prompt := fmt.Sprintf(`Create a calendar event based on this task.

Task: %s
%s
%s
Current time: %s

Return ONLY a JSON object:
{
  "title": "Event title",
  "start_time": "ISO 8601 datetime",
  "end_time": "ISO 8601 datetime",
  "attendees": ["list of attendees if mentioned"],
  "body": "Event description/agenda"
}

Guidelines:
- Default duration is 30 minutes for calls, 1 hour for meetings
- If no time specified, suggest next business day at 10 AM`,
		task.Title, func() string {
			if task.Description != nil {
				return "Description: " + *task.Description
			}
			return ""
		}(), dueInfo, now.Format(time.RFC3339))

	resp, err := h.llm.Complete(c.Context(), llm.CompletionRequest{
		Messages: []llm.Message{
			{Role: "user", Content: prompt},
		},
		MaxTokens:   400,
		Temperature: 0.4,
	})
	if err != nil {
		return httputil.ServiceUnavailable(c, "AI service error")
	}

	var draft DraftContent
	if err := json.Unmarshal([]byte(resp.Content), &draft); err != nil {
		return httputil.InternalError(c, "failed to parse AI response")
	}
	draft.Type = "calendar"

	// Save draft
	var draftID uuid.UUID
	if h.aiService != nil {
		draftID, _ = h.aiService.SaveDraft(c.Context(), userID, taskID, &draft)
	}

	return httputil.Success(c, map[string]interface{}{
		"draft_id": draftID,
		"draft":    draft,
	})
}

// Sync handles task synchronization
func (h *TaskHandler) Sync(c *fiber.Ctx) error {
	// TODO: Implement proper sync with conflict resolution
	return httputil.Success(c, dto.SyncResponse{
		ServerTimestamp: time.Now(),
		Changes:         []dto.SyncOperation{},
	})
}

// Helper functions

func (h *TaskHandler) getTask(ctx context.Context, taskID, userID uuid.UUID) (*models.Task, int, error) {
	var task models.Task
	var childCount int
	var entitiesJSON []byte
	var duplicateOfJSON []byte

	err := h.db.QueryRow(ctx,
		`SELECT t.id, t.user_id, t.title, t.description, t.ai_cleaned_title, t.ai_cleaned_description,
		 t.status, t.priority, t.due_at, t.has_due_time, t.completed_at, t.tags,
		 t.parent_id, t.depth, COALESCE(t.complexity, 0), COALESCE(t.ai_extracted_due, false),
		 COALESCE(t.skip_auto_cleanup, false), t.ai_entities, COALESCE(t.duplicate_of, '[]'), COALESCE(t.duplicate_resolved, false),
		 t.version, t.created_at, t.updated_at,
		 (SELECT COUNT(*) FROM tasks WHERE parent_id = t.id AND deleted_at IS NULL) as children_count
		 FROM tasks t
		 WHERE t.id = $1 AND t.user_id = $2 AND t.deleted_at IS NULL`,
		taskID, userID,
	).Scan(
		&task.ID, &task.UserID, &task.Title, &task.Description, &task.AICleanedTitle, &task.AICleanedDescription,
		&task.Status, &task.Priority, &task.DueAt, &task.HasDueTime, &task.CompletedAt, &task.Tags,
		&task.ParentID, &task.Depth, &task.Complexity, &task.AIExtractedDue,
		&task.SkipAutoCleanup, &entitiesJSON, &duplicateOfJSON, &task.DuplicateResolved,
		&task.Version, &task.CreatedAt, &task.UpdatedAt, &childCount,
	)

	if err == pgx.ErrNoRows {
		return nil, 0, fiber.NewError(fiber.StatusNotFound, "task not found")
	}
	if err != nil {
		return nil, 0, fiber.NewError(fiber.StatusInternalServerError, "database error")
	}

	// Parse entities from JSON
	if len(entitiesJSON) > 0 {
		_ = json.Unmarshal(entitiesJSON, &task.Entities)
	}
	if task.Entities == nil {
		task.Entities = []models.TaskEntity{}
	}

	// Parse duplicate_of from JSON
	if len(duplicateOfJSON) > 0 {
		_ = json.Unmarshal(duplicateOfJSON, &task.DuplicateOf)
	}
	if task.DuplicateOf == nil {
		task.DuplicateOf = []string{}
	}

	return &task, childCount, nil
}

func scanTask(rows pgx.Rows) (*models.Task, int, error) {
	var task models.Task
	var childCount int
	var entitiesJSON []byte
	var duplicateOfJSON []byte

	err := rows.Scan(
		&task.ID, &task.Title, &task.Description, &task.AICleanedTitle, &task.AICleanedDescription,
		&task.Status, &task.Priority, &task.DueAt, &task.HasDueTime, &task.CompletedAt, &task.Tags,
		&task.ParentID, &task.Depth, &task.SortOrder, &task.Complexity,
		&entitiesJSON, &duplicateOfJSON, &task.DuplicateResolved,
		&task.CreatedAt, &task.UpdatedAt, &childCount,
	)
	if err != nil {
		return nil, 0, err
	}

	// Parse entities from JSON
	if len(entitiesJSON) > 0 {
		_ = json.Unmarshal(entitiesJSON, &task.Entities)
	}
	if task.Entities == nil {
		task.Entities = []models.TaskEntity{}
	}

	// Parse duplicate_of from JSON
	if len(duplicateOfJSON) > 0 {
		_ = json.Unmarshal(duplicateOfJSON, &task.DuplicateOf)
	}
	if task.DuplicateOf == nil {
		task.DuplicateOf = []string{}
	}

	// Compute display fields
	task.ComputeDisplayFields()

	return &task, childCount, nil
}

func toTaskResponse(t *models.Task, childCount int) TaskResponse {
	entities := t.Entities
	if entities == nil {
		entities = []models.TaskEntity{}
	}

	duplicateOf := t.DuplicateOf
	if duplicateOf == nil {
		duplicateOf = []string{}
	}

	// Ensure display fields are computed
	t.ComputeDisplayFields()

	resp := TaskResponse{
		ID:                 t.ID.String(),
		Title:              t.Title,
		Description:        t.Description,
		AICleanedTitle:     t.AICleanedTitle,
		AICleanedDesc:      t.AICleanedDescription,
		DisplayTitle:       t.DisplayTitle,
		DisplayDescription: t.DisplayDescription,
		Status:             string(t.Status),
		Priority:           int(t.Priority),
		HasDueTime:         t.HasDueTime,
		Tags:               t.Tags,
		Depth:              t.Depth,
		SortOrder:          t.SortOrder,
		Complexity:         t.Complexity,
		HasChildren:        childCount > 0,
		ChildrenCount:      childCount,
		Entities:           entities,
		DuplicateOf:        duplicateOf,
		DuplicateResolved:  t.DuplicateResolved,
		CreatedAt:          t.CreatedAt.Format(time.RFC3339),
		UpdatedAt:          t.UpdatedAt.Format(time.RFC3339),
	}

	if t.DueAt != nil {
		d := t.DueAt.Format(time.RFC3339)
		resp.DueAt = &d
	}
	if t.CompletedAt != nil {
		d := t.CompletedAt.Format(time.RFC3339)
		resp.CompletedAt = &d
	}
	if t.ParentID != nil {
		p := t.ParentID.String()
		resp.ParentID = &p
	}

	return resp
}

// =====================================================
// Attachment Endpoints
// =====================================================

// AttachmentResponse represents an attachment in API responses
type AttachmentResponse struct {
	ID           string         `json:"id"`
	TaskID       string         `json:"task_id"`
	Type         string         `json:"type"`
	Name         string         `json:"name"`
	URL          string         `json:"url"`
	MimeType     *string        `json:"mime_type,omitempty"`
	SizeBytes    *int64         `json:"size_bytes,omitempty"`
	ThumbnailURL *string        `json:"thumbnail_url,omitempty"`
	Metadata     map[string]any `json:"metadata,omitempty"`
	CreatedAt    string         `json:"created_at"`
}

// CreateLinkAttachmentRequest represents a link attachment creation request
type CreateLinkAttachmentRequest struct {
	Name string `json:"name"`
	URL  string `json:"url"`
}

// CreateAttachment creates a new attachment for a task
func (h *TaskHandler) CreateAttachment(c *fiber.Ctx) error {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		return httputil.Unauthorized(c, "")
	}

	taskID, err := uuid.Parse(c.Params("id"))
	if err != nil {
		return httputil.BadRequest(c, "invalid task ID")
	}

	// Verify task exists and belongs to user
	var exists bool
	err = h.db.QueryRow(c.Context(),
		"SELECT EXISTS(SELECT 1 FROM tasks WHERE id = $1 AND user_id = $2 AND deleted_at IS NULL)",
		taskID, userID,
	).Scan(&exists)
	if err != nil || !exists {
		return httputil.NotFound(c, "task")
	}

	// Check if it's a link attachment (JSON) or file upload (multipart)
	contentType := c.Get("Content-Type")
	if strings.Contains(contentType, "application/json") {
		return h.createLinkAttachment(c, taskID, userID)
	}
	return h.createFileAttachment(c, taskID, userID)
}

func (h *TaskHandler) createLinkAttachment(c *fiber.Ctx, taskID, userID uuid.UUID) error {
	var req CreateLinkAttachmentRequest
	if err := c.BodyParser(&req); err != nil {
		return httputil.BadRequest(c, "invalid request body")
	}

	if req.URL == "" {
		return httputil.ValidationError(c, "validation failed", map[string]string{
			"url": "required",
		})
	}

	// Use URL as name if not provided
	name := req.Name
	if name == "" {
		name = req.URL
	}

	attachment := models.NewLinkAttachment(taskID, userID, name, req.URL)

	metadataJSON, _ := json.Marshal(attachment.Metadata)
	_, err := h.db.Exec(c.Context(),
		`INSERT INTO task_attachments (id, task_id, user_id, type, name, url, metadata, created_at)
		 VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
		attachment.ID, attachment.TaskID, attachment.UserID, attachment.Type,
		attachment.Name, attachment.URL, metadataJSON, attachment.CreatedAt,
	)
	if err != nil {
		return httputil.InternalError(c, "failed to create attachment")
	}

	return httputil.Created(c, toAttachmentResponse(attachment))
}

func (h *TaskHandler) createFileAttachment(c *fiber.Ctx, taskID, userID uuid.UUID) error {
	// Parse multipart form
	file, err := c.FormFile("file")
	if err != nil {
		return httputil.BadRequest(c, "file is required")
	}

	// Check file size (max 10MB for database storage)
	const maxSize = 10 * 1024 * 1024 // 10MB
	if file.Size > maxSize {
		return httputil.BadRequest(c, "file too large (max 10MB)")
	}

	// Read file content
	f, err := file.Open()
	if err != nil {
		return httputil.InternalError(c, "failed to read file")
	}
	defer f.Close()

	data := make([]byte, file.Size)
	if _, err := f.Read(data); err != nil {
		return httputil.InternalError(c, "failed to read file content")
	}

	// Determine mime type
	mimeType := file.Header.Get("Content-Type")
	if mimeType == "" {
		mimeType = "application/octet-stream"
	}

	// Create attachment
	attachment := models.NewFileAttachmentWithData(taskID, userID, file.Filename, mimeType, data)

	// Insert into database with data
	metadataJSON, _ := json.Marshal(attachment.Metadata)
	_, err = h.db.Exec(c.Context(),
		`INSERT INTO task_attachments (id, task_id, user_id, type, name, url, mime_type, size_bytes, data, metadata, created_at)
		 VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)`,
		attachment.ID, attachment.TaskID, attachment.UserID, attachment.Type,
		attachment.Name, "", attachment.MimeType, attachment.SizeBytes, attachment.Data, metadataJSON, attachment.CreatedAt,
	)
	if err != nil {
		return httputil.InternalError(c, "failed to create attachment")
	}

	// Set URL to download endpoint (relative to API base /api/v1)
	attachment.URL = fmt.Sprintf("/tasks/%s/attachments/%s/download", taskID.String(), attachment.ID.String())
	attachment.Data = nil // Don't return data in response

	return httputil.Created(c, toAttachmentResponse(attachment))
}

// DownloadAttachment serves the file content for a stored attachment
func (h *TaskHandler) DownloadAttachment(c *fiber.Ctx) error {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		return httputil.Unauthorized(c, "")
	}

	attachmentID, err := uuid.Parse(c.Params("attachmentId"))
	if err != nil {
		return httputil.BadRequest(c, "invalid attachment ID")
	}

	var attachment models.Attachment

	err = h.db.QueryRow(c.Context(),
		`SELECT id, name, mime_type, data
		 FROM task_attachments
		 WHERE id = $1 AND user_id = $2 AND deleted_at IS NULL`,
		attachmentID, userID,
	).Scan(&attachment.ID, &attachment.Name, &attachment.MimeType, &attachment.Data)

	if err != nil {
		return httputil.NotFound(c, "attachment")
	}

	if attachment.Data == nil {
		return httputil.BadRequest(c, "attachment has no stored data")
	}

	// Set content type and filename headers
	mimeType := "application/octet-stream"
	if attachment.MimeType != nil {
		mimeType = *attachment.MimeType
	}

	c.Set("Content-Type", mimeType)
	c.Set("Content-Disposition", fmt.Sprintf("inline; filename=\"%s\"", attachment.Name))

	return c.Send(attachment.Data)
}

// GetAttachments returns all attachments for a task
func (h *TaskHandler) GetAttachments(c *fiber.Ctx) error {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		return httputil.Unauthorized(c, "")
	}

	taskID, err := uuid.Parse(c.Params("id"))
	if err != nil {
		return httputil.BadRequest(c, "invalid task ID")
	}

	rows, err := h.db.Query(c.Context(),
		`SELECT id, task_id, user_id, type, name, url, mime_type, size_bytes, thumbnail_url, metadata, created_at, data
		 FROM task_attachments
		 WHERE task_id = $1 AND user_id = $2 AND deleted_at IS NULL
		 ORDER BY created_at DESC`,
		taskID, userID,
	)
	if err != nil {
		return httputil.InternalError(c, "database error")
	}
	defer rows.Close()

	attachments := make([]AttachmentResponse, 0)
	for rows.Next() {
		var a models.Attachment
		var metadataJSON []byte
		var data []byte

		if err := rows.Scan(&a.ID, &a.TaskID, &a.UserID, &a.Type, &a.Name, &a.URL,
			&a.MimeType, &a.SizeBytes, &a.ThumbnailURL, &metadataJSON, &a.CreatedAt, &data); err != nil {
			continue
		}

		if metadataJSON != nil {
			_ = json.Unmarshal(metadataJSON, &a.Metadata)
		}

		// For images and documents stored in DB, return data as base64 data URL for direct display
		// This avoids auth issues when opening in browser or external apps
		if data != nil && (a.Type == models.AttachmentTypeImage || a.Type == models.AttachmentTypeDocument) {
			mimeType := "application/octet-stream"
			if a.MimeType != nil {
				mimeType = *a.MimeType
			} else if a.Type == models.AttachmentTypeImage {
				mimeType = "image/png"
			}
			a.URL = fmt.Sprintf("data:%s;base64,%s", mimeType, base64.StdEncoding.EncodeToString(data))
		} else if a.URL == "" && (a.Type == models.AttachmentTypeImage || a.Type == models.AttachmentTypeDocument) {
			// Fallback: construct the download URL (relative to API base /api/v1)
			a.URL = fmt.Sprintf("/tasks/%s/attachments/%s/download", a.TaskID.String(), a.ID.String())
		}

		attachments = append(attachments, toAttachmentResponse(&a))
	}

	return httputil.Success(c, attachments)
}

// DeleteAttachment deletes an attachment
func (h *TaskHandler) DeleteAttachment(c *fiber.Ctx) error {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		return httputil.Unauthorized(c, "")
	}

	attachmentID, err := uuid.Parse(c.Params("attachmentId"))
	if err != nil {
		return httputil.BadRequest(c, "invalid attachment ID")
	}

	result, err := h.db.Exec(c.Context(),
		`UPDATE task_attachments SET deleted_at = $1
		 WHERE id = $2 AND user_id = $3 AND deleted_at IS NULL`,
		time.Now(), attachmentID, userID,
	)
	if err != nil {
		return httputil.InternalError(c, "failed to delete attachment")
	}

	if result.RowsAffected() == 0 {
		return httputil.NotFound(c, "attachment")
	}

	return httputil.NoContent(c)
}

// GetPresignedUploadURL returns a presigned URL for uploading a file
func (h *TaskHandler) GetPresignedUploadURL(c *fiber.Ctx) error {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		return httputil.Unauthorized(c, "")
	}

	taskID, err := uuid.Parse(c.Params("id"))
	if err != nil {
		return httputil.BadRequest(c, "invalid task ID")
	}

	var req struct {
		Filename string `json:"filename"`
		MimeType string `json:"mime_type"`
		Size     int64  `json:"size"`
	}
	if err := c.BodyParser(&req); err != nil {
		return httputil.BadRequest(c, "invalid request body")
	}

	// Verify task exists and belongs to user
	var exists bool
	err = h.db.QueryRow(c.Context(),
		"SELECT EXISTS(SELECT 1 FROM tasks WHERE id = $1 AND user_id = $2 AND deleted_at IS NULL)",
		taskID, userID,
	).Scan(&exists)
	if err != nil || !exists {
		return httputil.NotFound(c, "task")
	}

	// In a full implementation, this would:
	// 1. Generate a unique S3 key
	// 2. Create a presigned PUT URL
	// 3. Create a pending attachment record
	// 4. Return the URL and attachment ID

	// For now, return a placeholder response
	return httputil.Success(c, map[string]any{
		"message":       "presigned URL generation not yet implemented",
		"attachment_id": uuid.New().String(),
		"upload_url":    "https://s3.example.com/presigned-url",
		"expires_in":    3600,
	})
}

func toAttachmentResponse(a *models.Attachment) AttachmentResponse {
	return AttachmentResponse{
		ID:           a.ID.String(),
		TaskID:       a.TaskID.String(),
		Type:         string(a.Type),
		Name:         a.Name,
		URL:          a.URL,
		MimeType:     a.MimeType,
		SizeBytes:    a.SizeBytes,
		ThumbnailURL: a.ThumbnailURL,
		Metadata:     a.Metadata,
		CreatedAt:    a.CreatedAt.Format(time.RFC3339),
	}
}

// =====================================================
// Auto AI Processing
// =====================================================

// autoProcessTaskWithAI processes a task with AI in the background
func (h *TaskHandler) autoProcessTaskWithAI(ctx context.Context, userID uuid.UUID, task *models.Task) {
	if h.aiService == nil || h.llm == nil {
		return
	}

	// Use a fresh context since the original may be cancelled
	bgCtx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	description := ""
	if task.Description != nil {
		description = *task.Description
	}

	result, err := h.aiService.ProcessTaskOnSave(bgCtx, userID, task.ID, task.Title, description)
	if err != nil {
		// Log error but don't fail
		return
	}

	// Update task with AI results
	h.applyAIResultsToTask(bgCtx, userID, task.ID, result)
}

// applyAIResultsToTask updates the task with AI processing results
func (h *TaskHandler) applyAIResultsToTask(ctx context.Context, userID, taskID uuid.UUID, result *AIProcessResult) {
	if result == nil {
		return
	}

	// Build dynamic update query
	updates := []string{}
	args := []interface{}{}
	argNum := 1

	// Store cleaned title in ai_cleaned_title (don't modify original title)
	if result.CleanedTitle != nil {
		updates = append(updates, fmt.Sprintf("ai_cleaned_title = $%d", argNum))
		args = append(args, *result.CleanedTitle)
		argNum++
	}

	if result.DueAt != nil {
		updates = append(updates, fmt.Sprintf("due_at = $%d", argNum))
		args = append(args, *result.DueAt)
		argNum++
		// AI extraction sets has_due_time based on whether time was extracted
		updates = append(updates, fmt.Sprintf("has_due_time = $%d", argNum))
		args = append(args, result.HasDueTime)
		argNum++
		updates = append(updates, "ai_extracted_due = true")
	}

	if result.Complexity != nil {
		updates = append(updates, fmt.Sprintf("complexity = $%d", argNum))
		args = append(args, *result.Complexity)
		argNum++
	}

	if len(result.Entities) > 0 {
		entitiesJSON, _ := json.Marshal(result.Entities)
		updates = append(updates, fmt.Sprintf("ai_entities = $%d", argNum))
		args = append(args, entitiesJSON)
		argNum++
	}

	if len(updates) == 0 {
		// Only save draft if generated
		if result.Draft != nil {
			h.aiService.SaveDraft(ctx, userID, taskID, result.Draft)
		}
		return
	}

	// Add timestamp update
	updates = append(updates, fmt.Sprintf("updated_at = $%d", argNum))
	args = append(args, time.Now())
	argNum++

	// Add version increment
	updates = append(updates, "version = version + 1")

	// Add WHERE clause args
	args = append(args, taskID, userID)

	query := fmt.Sprintf(
		"UPDATE tasks SET %s WHERE id = $%d AND user_id = $%d",
		strings.Join(updates, ", "),
		argNum,
		argNum+1,
	)

	_, _ = h.db.Exec(ctx, query, args...)

	// Save draft if generated
	if result.Draft != nil {
		h.aiService.SaveDraft(ctx, userID, taskID, result.Draft)
	}
}

// =====================================================
// AI Endpoints
// =====================================================

// GetAIUsage returns AI usage stats for the current user
func (h *TaskHandler) GetAIUsage(c *fiber.Ctx) error {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		return httputil.Unauthorized(c, "")
	}

	if h.aiService == nil {
		return httputil.ServiceUnavailable(c, "AI service not available")
	}

	stats, err := h.aiService.GetUsageStats(c.Context(), userID)
	if err != nil {
		return httputil.InternalError(c, "failed to get usage stats")
	}

	return httputil.Success(c, stats)
}

// GetAIDrafts returns pending AI drafts for the current user
func (h *TaskHandler) GetAIDrafts(c *fiber.Ctx) error {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		return httputil.Unauthorized(c, "")
	}

	if h.aiService == nil {
		return httputil.ServiceUnavailable(c, "AI service not available")
	}

	drafts, err := h.aiService.GetPendingDrafts(c.Context(), userID)
	if err != nil {
		return httputil.InternalError(c, "failed to get drafts")
	}

	return httputil.Success(c, drafts)
}

// ApproveDraft marks a draft as approved and optionally sends it
func (h *TaskHandler) ApproveDraft(c *fiber.Ctx) error {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		return httputil.Unauthorized(c, "")
	}

	draftID, err := uuid.Parse(c.Params("id"))
	if err != nil {
		return httputil.BadRequest(c, "invalid draft ID")
	}

	var req struct {
		Send bool `json:"send"` // Whether to actually send (email/calendar)
	}
	_ = c.BodyParser(&req)

	// Mark draft as approved
	_, err = h.db.Exec(c.Context(),
		`UPDATE ai_drafts SET status = $1
		 WHERE id = $2 AND user_id = $3 AND status = 'draft'`,
		func() string { if req.Send { return "sent" }; return "approved" }(),
		draftID, userID,
	)
	if err != nil {
		return httputil.InternalError(c, "failed to approve draft")
	}

	// TODO: Implement actual send functionality for email/calendar
	// This would integrate with SMTP for email or Google Calendar API

	return httputil.Success(c, map[string]string{"status": "approved"})
}

// DeleteDraft cancels a draft
func (h *TaskHandler) DeleteDraft(c *fiber.Ctx) error {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		return httputil.Unauthorized(c, "")
	}

	draftID, err := uuid.Parse(c.Params("id"))
	if err != nil {
		return httputil.BadRequest(c, "invalid draft ID")
	}

	result, err := h.db.Exec(c.Context(),
		`UPDATE ai_drafts SET status = 'cancelled'
		 WHERE id = $1 AND user_id = $2 AND status = 'draft'`,
		draftID, userID,
	)
	if err != nil {
		return httputil.InternalError(c, "failed to delete draft")
	}

	if result.RowsAffected() == 0 {
		return httputil.NotFound(c, "draft")
	}

	return httputil.NoContent(c)
}

// GetUserTier returns the current user's subscription tier
func (h *TaskHandler) GetUserTier(c *fiber.Ctx) error {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		return httputil.Unauthorized(c, "")
	}

	if h.aiService == nil {
		return httputil.Success(c, map[string]string{"tier": "free"})
	}

	tier, _ := h.aiService.GetUserTier(c.Context(), userID)

	return httputil.Success(c, map[string]interface{}{
		"tier": tier,
		"limits": featureLimits[tier],
	})
}

// =====================================================
// Entity Management Endpoints
// =====================================================

// MergeEntities creates an alias relationship between two entities
// The source entity becomes an alias of the target (canonical) entity
// Tasks are NOT modified - the alias is resolved when aggregating entities
func (h *TaskHandler) MergeEntities(c *fiber.Ctx) error {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		return httputil.Unauthorized(c, "")
	}

	var req struct {
		Type      string `json:"type"`
		FromValue string `json:"from_value"`
		ToValue   string `json:"to_value"`
	}
	if err := c.BodyParser(&req); err != nil {
		return httputil.BadRequest(c, "invalid request body")
	}

	if req.Type == "" || req.FromValue == "" || req.ToValue == "" {
		return httputil.BadRequest(c, "type, from_value, and to_value are required")
	}

	if req.FromValue == req.ToValue {
		return httputil.BadRequest(c, "cannot merge entity with itself")
	}

	// Insert alias (upsert - update if exists)
	_, err = h.db.Exec(c.Context(),
		`INSERT INTO entity_aliases (user_id, entity_type, alias_value, canonical_value)
		 VALUES ($1, $2, $3, $4)
		 ON CONFLICT (user_id, entity_type, alias_value)
		 DO UPDATE SET canonical_value = $4`,
		userID, req.Type, req.FromValue, req.ToValue,
	)
	if err != nil {
		return httputil.InternalError(c, "failed to create entity alias")
	}

	return httputil.Success(c, map[string]interface{}{
		"message": fmt.Sprintf("'%s' is now an alias of '%s'", req.FromValue, req.ToValue),
	})
}

// RemoveEntityFromAllTasks removes an entity from all tasks that have it
// This actually modifies the ai_entities field of affected tasks
func (h *TaskHandler) RemoveEntityFromAllTasks(c *fiber.Ctx) error {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		return httputil.Unauthorized(c, "")
	}

	entityType := c.Params("type")
	entityValue := c.Params("value")

	if entityType == "" || entityValue == "" {
		return httputil.BadRequest(c, "entity type and value are required")
	}

	// Find all tasks that have this entity
	rows, err := h.db.Query(c.Context(),
		`SELECT id, ai_entities FROM tasks
		 WHERE user_id = $1 AND deleted_at IS NULL
		 AND ai_entities @> $2::jsonb`,
		userID, fmt.Sprintf(`[{"type":"%s","value":"%s"}]`, entityType, entityValue),
	)
	if err != nil {
		return httputil.InternalError(c, "database error")
	}
	defer rows.Close()

	updatedCount := 0
	for rows.Next() {
		var taskID uuid.UUID
		var entitiesJSON []byte
		if err := rows.Scan(&taskID, &entitiesJSON); err != nil {
			continue
		}

		// Parse entities and filter out the one to remove
		var entities []models.TaskEntity
		if err := json.Unmarshal(entitiesJSON, &entities); err != nil {
			continue
		}

		newEntities := make([]models.TaskEntity, 0, len(entities))
		for _, e := range entities {
			if !(strings.EqualFold(e.Type, entityType) && strings.EqualFold(e.Value, entityValue)) {
				newEntities = append(newEntities, e)
			}
		}

		// Update task with new entities
		newEntitiesJSON, _ := json.Marshal(newEntities)
		_, err = h.db.Exec(c.Context(),
			`UPDATE tasks SET ai_entities = $1, version = version + 1, updated_at = NOW()
			 WHERE id = $2 AND user_id = $3`,
			newEntitiesJSON, taskID, userID,
		)
		if err == nil {
			updatedCount++
		}
	}

	// Also remove any aliases where this entity is the canonical value
	_, _ = h.db.Exec(c.Context(),
		`DELETE FROM entity_aliases
		 WHERE user_id = $1 AND entity_type = $2 AND canonical_value = $3`,
		userID, entityType, entityValue,
	)

	// Also remove alias if this entity was an alias
	_, _ = h.db.Exec(c.Context(),
		`DELETE FROM entity_aliases
		 WHERE user_id = $1 AND entity_type = $2 AND alias_value = $3`,
		userID, entityType, entityValue,
	)

	return httputil.Success(c, map[string]interface{}{
		"message":       fmt.Sprintf("Removed '%s' from %d tasks", entityValue, updatedCount),
		"updated_count": updatedCount,
	})
}

// GetEntityAliases returns all aliases for a specific canonical entity
func (h *TaskHandler) GetEntityAliases(c *fiber.Ctx) error {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		return httputil.Unauthorized(c, "")
	}

	entityType := c.Params("type")
	entityValue := c.Params("value")

	if entityType == "" || entityValue == "" {
		return httputil.BadRequest(c, "entity type and value are required")
	}

	rows, err := h.db.Query(c.Context(),
		`SELECT alias_value, created_at FROM entity_aliases
		 WHERE user_id = $1 AND entity_type = $2 AND canonical_value = $3
		 ORDER BY created_at DESC`,
		userID, entityType, entityValue,
	)
	if err != nil {
		return httputil.InternalError(c, "database error")
	}
	defer rows.Close()

	aliases := make([]map[string]interface{}, 0)
	for rows.Next() {
		var aliasValue string
		var createdAt time.Time
		if err := rows.Scan(&aliasValue, &createdAt); err != nil {
			continue
		}
		aliases = append(aliases, map[string]interface{}{
			"value":      aliasValue,
			"created_at": createdAt.Format(time.RFC3339),
		})
	}

	return httputil.Success(c, map[string]interface{}{
		"canonical": entityValue,
		"type":      entityType,
		"aliases":   aliases,
	})
}
