package tasks

import (
	"context"
	"encoding/json"
	"fmt"
	"regexp"
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
	Title       string   `json:"title"`
	Description *string  `json:"description,omitempty"`
	DueDate     *string  `json:"due_date,omitempty"`
	Priority    *int     `json:"priority,omitempty"`
	Tags        []string `json:"tags,omitempty"`
	ParentID    *string  `json:"parent_id,omitempty"`
}

// UpdateRequest represents the task update request
type UpdateRequest struct {
	Title       *string  `json:"title,omitempty"`
	Description *string  `json:"description,omitempty"`
	DueDate     *string  `json:"due_date,omitempty"`
	Priority    *int     `json:"priority,omitempty"`
	Status      *string  `json:"status,omitempty"`
	Tags        []string `json:"tags,omitempty"`
	GroupID     *string  `json:"group_id,omitempty"`
}

// TaskResponse represents a task in API responses
type TaskResponse struct {
	ID              string                 `json:"id"`
	Title           string                 `json:"title"`
	Description     *string                `json:"description,omitempty"`
	AISummary       *string                `json:"ai_summary,omitempty"`
	AISteps         []commonModels.TaskStep `json:"ai_steps,omitempty"`
	Status          string                 `json:"status"`
	Priority        int                    `json:"priority"`
	DueDate         *string                `json:"due_date,omitempty"`
	CompletedAt     *string                `json:"completed_at,omitempty"`
	Tags            []string               `json:"tags"`
	ParentID        *string                `json:"parent_id,omitempty"`
	Depth           int                    `json:"depth"`
	Complexity      int                    `json:"complexity"`
	GroupID         *string                `json:"group_id,omitempty"`
	GroupName       *string                `json:"group_name,omitempty"`
	HasChildren     bool                   `json:"has_children"`
	ChildrenCount   int                    `json:"children_count"`
	CreatedAt       string                 `json:"created_at"`
	UpdatedAt       string                 `json:"updated_at"`
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
	task.Description = req.Description

	if req.DueDate != nil {
		dueDate, err := time.Parse(time.RFC3339, *req.DueDate)
		if err != nil {
			return httputil.BadRequest(c, "invalid due_date format")
		}
		task.DueDate = &dueDate
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

	// Process hashtags (Bear-style #List/Sublist)
	_ = h.ProcessHashtagsForTask(c.Context(), userID, task)

	// Insert task
	aiStepsJSON, _ := task.AIStepsJSON()
	entitiesJSON, _ := json.Marshal(task.Entities)

	_, err = h.db.Exec(c.Context(),
		`INSERT INTO tasks (id, user_id, title, description, status, priority, due_date, tags,
		 parent_id, depth, ai_steps, entities, group_id, version, created_at, updated_at)
		 VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16)`,
		task.ID, task.UserID, task.Title, task.Description, task.Status, task.Priority,
		task.DueDate, task.Tags, task.ParentID, task.Depth, aiStepsJSON, entitiesJSON,
		task.GroupID, task.Version, task.CreatedAt, task.UpdatedAt,
	)
	if err != nil {
		return httputil.InternalError(c, "failed to create task")
	}

	// Update task_count for the list (if task was assigned to one)
	if task.GroupID != nil {
		h.updateListTaskCount(c.Context(), *task.GroupID)
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
func (h *TaskHandler) List(c *fiber.Ctx) error {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		return httputil.Unauthorized(c, "")
	}

	pagination := httputil.ParsePagination(c)

	// Get tasks
	rows, err := h.db.Query(c.Context(),
		`SELECT t.id, t.title, t.description, t.ai_summary, t.ai_steps, t.status, t.priority,
		 t.due_date, t.completed_at, t.tags, t.parent_id, t.depth, t.complexity,
		 t.group_id, g.name as group_name, t.created_at, t.updated_at,
		 (SELECT COUNT(*) FROM tasks WHERE parent_id = t.id AND deleted_at IS NULL) as children_count
		 FROM tasks t
		 LEFT JOIN task_groups g ON t.group_id = g.id
		 WHERE t.user_id = $1 AND t.deleted_at IS NULL AND t.parent_id IS NULL
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

	// Get total count
	var totalCount int64
	_ = h.db.QueryRow(c.Context(),
		"SELECT COUNT(*) FROM tasks WHERE user_id = $1 AND deleted_at IS NULL AND parent_id IS NULL",
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
		`SELECT t.id, t.title, t.description, t.ai_summary, t.ai_steps, t.status, t.priority,
		 t.due_date, t.completed_at, t.tags, t.parent_id, t.depth, t.complexity,
		 t.group_id, g.name as group_name, t.created_at, t.updated_at,
		 (SELECT COUNT(*) FROM tasks WHERE parent_id = t.id AND deleted_at IS NULL) as children_count
		 FROM tasks t
		 LEFT JOIN task_groups g ON t.group_id = g.id
		 WHERE t.user_id = $1 AND t.deleted_at IS NULL
		 AND t.due_date >= $2 AND t.due_date < $3
		 AND t.status != 'completed'
		 ORDER BY t.priority DESC, t.due_date ASC`,
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
		`SELECT t.id, t.title, t.description, t.ai_summary, t.ai_steps, t.status, t.priority,
		 t.due_date, t.completed_at, t.tags, t.parent_id, t.depth, t.complexity,
		 t.group_id, g.name as group_name, t.created_at, t.updated_at,
		 (SELECT COUNT(*) FROM tasks WHERE parent_id = t.id AND deleted_at IS NULL) as children_count
		 FROM tasks t
		 LEFT JOIN task_groups g ON t.group_id = g.id
		 WHERE t.user_id = $1 AND t.deleted_at IS NULL
		 AND t.due_date IS NULL AND t.status != 'completed'
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
		`SELECT t.id, t.title, t.description, t.ai_summary, t.ai_steps, t.status, t.priority,
		 t.due_date, t.completed_at, t.tags, t.parent_id, t.depth, t.complexity,
		 t.group_id, g.name as group_name, t.created_at, t.updated_at,
		 (SELECT COUNT(*) FROM tasks WHERE parent_id = t.id AND deleted_at IS NULL) as children_count
		 FROM tasks t
		 LEFT JOIN task_groups g ON t.group_id = g.id
		 WHERE t.user_id = $1 AND t.deleted_at IS NULL
		 AND t.due_date >= $2 AND t.status != 'completed'
		 ORDER BY t.due_date ASC
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
		`SELECT t.id, t.title, t.description, t.ai_summary, t.ai_steps, t.status, t.priority,
		 t.due_date, t.completed_at, t.tags, t.parent_id, t.depth, t.complexity,
		 t.group_id, g.name as group_name, t.created_at, t.updated_at,
		 (SELECT COUNT(*) FROM tasks WHERE parent_id = t.id AND deleted_at IS NULL) as children_count
		 FROM tasks t
		 LEFT JOIN task_groups g ON t.group_id = g.id
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

	// Track old group_id for task_count updates
	oldGroupID := task.GroupID

	// Apply updates
	if req.Title != nil {
		task.Title = *req.Title
	}
	if req.Description != nil {
		task.Description = req.Description
	}
	if req.DueDate != nil {
		dueDate, err := time.Parse(time.RFC3339, *req.DueDate)
		if err != nil {
			return httputil.BadRequest(c, "invalid due_date format")
		}
		task.DueDate = &dueDate
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
	if req.GroupID != nil {
		groupID, err := uuid.Parse(*req.GroupID)
		if err != nil {
			return httputil.BadRequest(c, "invalid group_id")
		}
		task.GroupID = &groupID
	}

	// Process hashtags if title or description changed
	if req.Title != nil || req.Description != nil {
		_ = h.ProcessHashtagsForTask(c.Context(), userID, task)
	}

	task.IncrementVersion()

	// Update task
	_, err = h.db.Exec(c.Context(),
		`UPDATE tasks SET title = $1, description = $2, due_date = $3, priority = $4,
		 status = $5, completed_at = $6, tags = $7, group_id = $8, version = $9, updated_at = $10
		 WHERE id = $11 AND user_id = $12`,
		task.Title, task.Description, task.DueDate, task.Priority, task.Status,
		task.CompletedAt, task.Tags, task.GroupID, task.Version, task.UpdatedAt,
		taskID, userID,
	)
	if err != nil {
		return httputil.InternalError(c, "failed to update task")
	}

	// Update task_count for affected lists
	if oldGroupID != nil && (task.GroupID == nil || *oldGroupID != *task.GroupID) {
		h.updateListTaskCount(c.Context(), *oldGroupID)
	}
	if task.GroupID != nil && (oldGroupID == nil || *task.GroupID != *oldGroupID) {
		h.updateListTaskCount(c.Context(), *task.GroupID)
	}

	// Auto-process with AI if title or description changed (async)
	if req.Title != nil || req.Description != nil {
		go h.autoProcessTaskWithAI(c.Context(), userID, task)
	}

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

	// Get task group_id before deletion for task_count update
	var groupID *uuid.UUID
	_ = h.db.QueryRow(c.Context(),
		`SELECT group_id FROM tasks WHERE id = $1 AND user_id = $2 AND deleted_at IS NULL`,
		taskID, userID,
	).Scan(&groupID)

	// Soft delete task and children
	now := time.Now()
	_, err = h.db.Exec(c.Context(),
		`UPDATE tasks SET deleted_at = $1 WHERE (id = $2 OR parent_id = $2) AND user_id = $3`,
		now, taskID, userID,
	)
	if err != nil {
		return httputil.InternalError(c, "failed to delete task")
	}

	// Update task_count for the list
	if groupID != nil {
		h.updateListTaskCount(c.Context(), *groupID)
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

	// Get task group_id for task_count update
	var groupID *uuid.UUID
	_ = h.db.QueryRow(c.Context(),
		`SELECT group_id FROM tasks WHERE id = $1 AND user_id = $2 AND deleted_at IS NULL`,
		taskID, userID,
	).Scan(&groupID)

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

	// Update task_count for the list (completed tasks don't count)
	if groupID != nil {
		h.updateListTaskCount(c.Context(), *groupID)
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

	// Get task group_id for task_count update
	var groupID *uuid.UUID
	_ = h.db.QueryRow(c.Context(),
		`SELECT group_id FROM tasks WHERE id = $1 AND user_id = $2 AND deleted_at IS NULL`,
		taskID, userID,
	).Scan(&groupID)

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

	// Update task_count for the list (uncompleted task now counts again)
	if groupID != nil {
		h.updateListTaskCount(c.Context(), *groupID)
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

	task := models.NewTask(userID, req.Title)
	task.Description = req.Description
	task.ParentID = &parentID
	task.Depth = parentDepth + 1

	if req.Priority != nil {
		task.Priority = commonModels.Priority(*req.Priority)
	}

	aiStepsJSON, _ := task.AIStepsJSON()
	entitiesJSON, _ := json.Marshal(task.Entities)

	_, err = h.db.Exec(c.Context(),
		`INSERT INTO tasks (id, user_id, title, description, status, priority, due_date, tags,
		 parent_id, depth, ai_steps, entities, version, created_at, updated_at)
		 VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15)`,
		task.ID, task.UserID, task.Title, task.Description, task.Status, task.Priority,
		task.DueDate, task.Tags, task.ParentID, task.Depth, aiStepsJSON, entitiesJSON,
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
		`SELECT t.id, t.title, t.description, t.ai_summary, t.ai_steps, t.status, t.priority,
		 t.due_date, t.completed_at, t.tags, t.parent_id, t.depth, t.complexity,
		 t.group_id, NULL as group_name, t.created_at, t.updated_at,
		 0 as children_count
		 FROM tasks t
		 WHERE t.user_id = $1 AND t.parent_id = $2 AND t.deleted_at IS NULL
		 ORDER BY t.created_at ASC`,
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

// AIDecompose uses AI to break down a task into steps
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

	// Call LLM to decompose task
	prompt := fmt.Sprintf(`Break down this task into 2-5 actionable steps.
Task: %s
%s

Return ONLY a JSON array of steps, like:
[
  {"step": 1, "action": "First action", "done": false},
  {"step": 2, "action": "Second action", "done": false}
]`, task.Title, func() string {
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

	// Parse AI response
	var steps []commonModels.TaskStep
	if err := json.Unmarshal([]byte(resp.Content), &steps); err != nil {
		// Try to extract JSON from response
		return httputil.InternalError(c, "failed to parse AI response")
	}

	// Update task with AI steps
	task.AISteps = steps
	task.AIDecomposed = true
	task.IncrementVersion()

	aiStepsJSON, _ := task.AIStepsJSON()
	_, err = h.db.Exec(c.Context(),
		`UPDATE tasks SET ai_steps = $1, ai_decomposed = true, version = $2, updated_at = $3
		 WHERE id = $4 AND user_id = $5`,
		aiStepsJSON, task.Version, task.UpdatedAt, taskID, userID,
	)
	if err != nil {
		return httputil.InternalError(c, "failed to update task")
	}

	return httputil.Success(c, toTaskResponse(task, childCount))
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

	// Store original values before cleanup (for revert functionality)
	// Only store original if it differs from cleaned version
	if cleaned.Title != task.Title {
		task.OriginalTitle = &task.Title
	}
	if task.Description != nil && cleaned.Summary != "" && cleaned.Summary != *task.Description {
		task.OriginalDescription = task.Description
	}

	// Update with cleaned values
	task.Title = cleaned.Title
	if cleaned.Summary != "" {
		task.AISummary = &cleaned.Summary
	}
	task.AICleanedTitle = true
	task.IncrementVersion()

	_, err = h.db.Exec(c.Context(),
		`UPDATE tasks SET title = $1, ai_summary = $2, original_title = $3, original_description = $4,
		 ai_cleaned_title = true, version = $5, updated_at = $6
		 WHERE id = $7 AND user_id = $8`,
		task.Title, task.AISummary, task.OriginalTitle, task.OriginalDescription,
		task.Version, task.UpdatedAt, taskID, userID,
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
	if task.DueDate != nil {
		dueInfo = fmt.Sprintf("Due date: %s", task.DueDate.Format("2006-01-02 15:04"))
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
	if task.DueDate != nil {
		dueInfo = fmt.Sprintf("Due/scheduled: %s", task.DueDate.Format("2006-01-02 15:04"))
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

// Group endpoints

// CreateGroup creates a task group
func (h *TaskHandler) CreateGroup(c *fiber.Ctx) error {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		return httputil.Unauthorized(c, "")
	}

	var req struct {
		Name  string  `json:"name"`
		Icon  *string `json:"icon,omitempty"`
		Color *string `json:"color,omitempty"`
	}
	if err := c.BodyParser(&req); err != nil {
		return httputil.BadRequest(c, "invalid request body")
	}

	if req.Name == "" {
		return httputil.ValidationError(c, "validation failed", map[string]string{
			"name": "required",
		})
	}

	id := uuid.New()
	now := time.Now()

	_, err = h.db.Exec(c.Context(),
		`INSERT INTO task_groups (id, user_id, name, icon, color, created_at, updated_at)
		 VALUES ($1, $2, $3, $4, $5, $6, $7)`,
		id, userID, req.Name, req.Icon, req.Color, now, now,
	)
	if err != nil {
		return httputil.InternalError(c, "failed to create group")
	}

	return httputil.Created(c, map[string]interface{}{
		"id":         id.String(),
		"name":       req.Name,
		"icon":       req.Icon,
		"color":      req.Color,
		"created_at": now.Format(time.RFC3339),
	})
}

// ListGroups lists task groups
func (h *TaskHandler) ListGroups(c *fiber.Ctx) error {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		return httputil.Unauthorized(c, "")
	}

	rows, err := h.db.Query(c.Context(),
		`SELECT id, name, icon, color, ai_created, created_at, updated_at
		 FROM task_groups WHERE user_id = $1 AND deleted_at IS NULL
		 ORDER BY name ASC`,
		userID,
	)
	if err != nil {
		return httputil.InternalError(c, "database error")
	}
	defer rows.Close()

	groups := make([]map[string]interface{}, 0)
	for rows.Next() {
		var id uuid.UUID
		var name string
		var icon, color *string
		var aiCreated bool
		var createdAt, updatedAt time.Time

		if err := rows.Scan(&id, &name, &icon, &color, &aiCreated, &createdAt, &updatedAt); err != nil {
			continue
		}

		groups = append(groups, map[string]interface{}{
			"id":         id.String(),
			"name":       name,
			"icon":       icon,
			"color":      color,
			"ai_created": aiCreated,
			"created_at": createdAt.Format(time.RFC3339),
			"updated_at": updatedAt.Format(time.RFC3339),
		})
	}

	return httputil.Success(c, groups)
}

// UpdateGroup updates a task group
func (h *TaskHandler) UpdateGroup(c *fiber.Ctx) error {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		return httputil.Unauthorized(c, "")
	}

	groupID, err := uuid.Parse(c.Params("id"))
	if err != nil {
		return httputil.BadRequest(c, "invalid group ID")
	}

	var req struct {
		Name  *string `json:"name,omitempty"`
		Icon  *string `json:"icon,omitempty"`
		Color *string `json:"color,omitempty"`
	}
	if err := c.BodyParser(&req); err != nil {
		return httputil.BadRequest(c, "invalid request body")
	}

	_, err = h.db.Exec(c.Context(),
		`UPDATE task_groups SET
		 name = COALESCE($1, name),
		 icon = COALESCE($2, icon),
		 color = COALESCE($3, color),
		 updated_at = $4
		 WHERE id = $5 AND user_id = $6 AND deleted_at IS NULL`,
		req.Name, req.Icon, req.Color, time.Now(), groupID, userID,
	)
	if err != nil {
		return httputil.InternalError(c, "failed to update group")
	}

	return httputil.Success(c, map[string]string{"message": "group updated"})
}

// DeleteGroup deletes a task group
func (h *TaskHandler) DeleteGroup(c *fiber.Ctx) error {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		return httputil.Unauthorized(c, "")
	}

	groupID, err := uuid.Parse(c.Params("id"))
	if err != nil {
		return httputil.BadRequest(c, "invalid group ID")
	}

	// Soft delete and ungroup tasks
	now := time.Now()
	_, _ = h.db.Exec(c.Context(),
		"UPDATE tasks SET group_id = NULL WHERE group_id = $1 AND user_id = $2",
		groupID, userID,
	)
	_, err = h.db.Exec(c.Context(),
		"UPDATE task_groups SET deleted_at = $1 WHERE id = $2 AND user_id = $3",
		now, groupID, userID,
	)
	if err != nil {
		return httputil.InternalError(c, "failed to delete group")
	}

	return httputil.NoContent(c)
}

// Helper functions

func (h *TaskHandler) getTask(ctx context.Context, taskID, userID uuid.UUID) (*models.Task, int, error) {
	var task models.Task
	var groupName *string
	var childCount int
	var aiStepsJSON []byte

	err := h.db.QueryRow(ctx,
		`SELECT t.id, t.user_id, t.title, t.description, t.ai_summary, t.ai_steps, t.status, t.priority,
		 t.due_date, t.completed_at, t.tags, t.parent_id, t.depth, COALESCE(t.complexity, 0),
		 t.group_id, g.name, COALESCE(t.ai_cleaned_title, false), COALESCE(t.ai_extracted_due, false), COALESCE(t.ai_decomposed, false),
		 t.original_title, t.original_description, COALESCE(t.skip_auto_cleanup, false), t.version, t.created_at, t.updated_at,
		 (SELECT COUNT(*) FROM tasks WHERE parent_id = t.id AND deleted_at IS NULL) as children_count
		 FROM tasks t
		 LEFT JOIN task_groups g ON t.group_id = g.id
		 WHERE t.id = $1 AND t.user_id = $2 AND t.deleted_at IS NULL`,
		taskID, userID,
	).Scan(
		&task.ID, &task.UserID, &task.Title, &task.Description, &task.AISummary, &aiStepsJSON,
		&task.Status, &task.Priority, &task.DueDate, &task.CompletedAt, &task.Tags,
		&task.ParentID, &task.Depth, &task.Complexity, &task.GroupID, &groupName,
		&task.AICleanedTitle, &task.AIExtractedDue, &task.AIDecomposed,
		&task.OriginalTitle, &task.OriginalDescription, &task.SkipAutoCleanup, &task.Version, &task.CreatedAt, &task.UpdatedAt, &childCount,
	)

	if err == pgx.ErrNoRows {
		return nil, 0, fiber.NewError(fiber.StatusNotFound, "task not found")
	}
	if err != nil {
		return nil, 0, fiber.NewError(fiber.StatusInternalServerError, "database error")
	}

	if aiStepsJSON != nil {
		_ = task.SetAIStepsFromJSON(aiStepsJSON)
	}
	task.GroupName = groupName

	return &task, childCount, nil
}

func scanTask(rows pgx.Rows) (*models.Task, int, error) {
	var task models.Task
	var groupName *string
	var childCount int
	var aiStepsJSON []byte

	err := rows.Scan(
		&task.ID, &task.Title, &task.Description, &task.AISummary, &aiStepsJSON,
		&task.Status, &task.Priority, &task.DueDate, &task.CompletedAt, &task.Tags,
		&task.ParentID, &task.Depth, &task.Complexity, &task.GroupID, &groupName,
		&task.CreatedAt, &task.UpdatedAt, &childCount,
	)
	if err != nil {
		return nil, 0, err
	}

	if aiStepsJSON != nil {
		_ = task.SetAIStepsFromJSON(aiStepsJSON)
	}
	task.GroupName = groupName

	return &task, childCount, nil
}

func toTaskResponse(t *models.Task, childCount int) TaskResponse {
	resp := TaskResponse{
		ID:            t.ID.String(),
		Title:         t.Title,
		Description:   t.Description,
		AISummary:     t.AISummary,
		AISteps:       t.AISteps,
		Status:        string(t.Status),
		Priority:      int(t.Priority),
		Tags:          t.Tags,
		Depth:         t.Depth,
		Complexity:    t.Complexity,
		HasChildren:   childCount > 0,
		ChildrenCount: childCount,
		CreatedAt:     t.CreatedAt.Format(time.RFC3339),
		UpdatedAt:     t.UpdatedAt.Format(time.RFC3339),
	}

	if t.DueDate != nil {
		d := t.DueDate.Format(time.RFC3339)
		resp.DueDate = &d
	}
	if t.CompletedAt != nil {
		d := t.CompletedAt.Format(time.RFC3339)
		resp.CompletedAt = &d
	}
	if t.ParentID != nil {
		p := t.ParentID.String()
		resp.ParentID = &p
	}
	if t.GroupID != nil {
		g := t.GroupID.String()
		resp.GroupID = &g
	}
	resp.GroupName = t.GroupName

	return resp
}

// =====================================================
// List Endpoints (Bear-style #List/Sublist)
// =====================================================

// ListResponse represents a list in API responses
type ListResponse struct {
	ID         string          `json:"id"`
	Name       string          `json:"name"`
	Icon       *string         `json:"icon,omitempty"`
	Color      *string         `json:"color,omitempty"`
	ParentID   *string         `json:"parent_id,omitempty"`
	Depth      int             `json:"depth"`
	TaskCount  int             `json:"task_count"`
	FullPath   string          `json:"full_path"`
	Archived   bool            `json:"archived"`
	ArchivedAt *string         `json:"archived_at,omitempty"`
	Children   []ListResponse  `json:"children,omitempty"`
	CreatedAt  string          `json:"created_at"`
	UpdatedAt  string          `json:"updated_at"`
}

// CreateListRequest represents a list creation request
type CreateListRequest struct {
	Name     string  `json:"name"`
	Icon     *string `json:"icon,omitempty"`
	Color    *string `json:"color,omitempty"`
	ParentID *string `json:"parent_id,omitempty"`
}

// ListLists returns all lists (flat)
// Query params: archived=true to get archived lists, archived=false (default) for active lists
func (h *TaskHandler) ListLists(c *fiber.Ctx) error {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		return httputil.Unauthorized(c, "")
	}

	// Check if we want archived lists
	showArchived := c.Query("archived", "false") == "true"

	rows, err := h.db.Query(c.Context(),
		`SELECT g.id, g.name, g.icon, g.color, g.parent_id, g.depth, g.task_count,
		 COALESCE(p.name || '/', '') || g.name as full_path,
		 COALESCE(g.archived, false), g.archived_at,
		 g.created_at, g.updated_at
		 FROM task_groups g
		 LEFT JOIN task_groups p ON g.parent_id = p.id AND p.deleted_at IS NULL
		 WHERE g.user_id = $1 AND g.deleted_at IS NULL AND COALESCE(g.archived, false) = $2
		 ORDER BY full_path ASC`,
		userID, showArchived,
	)
	if err != nil {
		return httputil.InternalError(c, "database error")
	}
	defer rows.Close()

	lists := make([]ListResponse, 0)
	for rows.Next() {
		var lr ListResponse
		var id uuid.UUID
		var parentID *uuid.UUID
		var archivedAt *time.Time
		var createdAt, updatedAt time.Time

		if err := rows.Scan(&id, &lr.Name, &lr.Icon, &lr.Color, &parentID, &lr.Depth,
			&lr.TaskCount, &lr.FullPath, &lr.Archived, &archivedAt, &createdAt, &updatedAt); err != nil {
			continue
		}

		lr.ID = id.String()
		lr.CreatedAt = createdAt.Format(time.RFC3339)
		lr.UpdatedAt = updatedAt.Format(time.RFC3339)
		if parentID != nil {
			p := parentID.String()
			lr.ParentID = &p
		}
		if archivedAt != nil {
			a := archivedAt.Format(time.RFC3339)
			lr.ArchivedAt = &a
		}
		lists = append(lists, lr)
	}

	return httputil.Success(c, lists)
}

// ListTree returns lists as a hierarchical tree
// Query params: archived=true to get archived lists, archived=false (default) for active lists
func (h *TaskHandler) ListTree(c *fiber.Ctx) error {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		return httputil.Unauthorized(c, "")
	}

	// Check if we want archived lists
	showArchived := c.Query("archived", "false") == "true"

	// Get all lists
	rows, err := h.db.Query(c.Context(),
		`SELECT id, name, icon, color, parent_id, depth, task_count,
		 COALESCE(archived, false), archived_at, created_at, updated_at
		 FROM task_groups
		 WHERE user_id = $1 AND deleted_at IS NULL AND COALESCE(archived, false) = $2
		 ORDER BY name ASC`,
		userID, showArchived,
	)
	if err != nil {
		return httputil.InternalError(c, "database error")
	}
	defer rows.Close()

	// Build a map for tree construction
	listMap := make(map[string]*ListResponse)
	var rootLists []ListResponse

	for rows.Next() {
		var id uuid.UUID
		var parentID *uuid.UUID
		var name string
		var icon, color *string
		var depth, taskCount int
		var archived bool
		var archivedAt *time.Time
		var createdAt, updatedAt time.Time

		if err := rows.Scan(&id, &name, &icon, &color, &parentID, &depth, &taskCount,
			&archived, &archivedAt, &createdAt, &updatedAt); err != nil {
			continue
		}

		lr := ListResponse{
			ID:        id.String(),
			Name:      name,
			Icon:      icon,
			Color:     color,
			Depth:     depth,
			TaskCount: taskCount,
			FullPath:  name,
			Archived:  archived,
			Children:  make([]ListResponse, 0),
			CreatedAt: createdAt.Format(time.RFC3339),
			UpdatedAt: updatedAt.Format(time.RFC3339),
		}
		if parentID != nil {
			p := parentID.String()
			lr.ParentID = &p
		}
		if archivedAt != nil {
			a := archivedAt.Format(time.RFC3339)
			lr.ArchivedAt = &a
		}

		listMap[lr.ID] = &lr
	}

	// Build tree structure
	for _, lr := range listMap {
		if lr.ParentID == nil {
			rootLists = append(rootLists, *lr)
		} else if parent, ok := listMap[*lr.ParentID]; ok {
			lr.FullPath = parent.Name + "/" + lr.Name
			parent.Children = append(parent.Children, *lr)
		}
	}

	// Update root lists with their children from the map
	for i := range rootLists {
		if mapItem, ok := listMap[rootLists[i].ID]; ok {
			rootLists[i].Children = mapItem.Children
		}
	}

	return httputil.Success(c, rootLists)
}

// CreateList creates a new list
func (h *TaskHandler) CreateList(c *fiber.Ctx) error {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		return httputil.Unauthorized(c, "")
	}

	var req CreateListRequest
	if err := c.BodyParser(&req); err != nil {
		return httputil.BadRequest(c, "invalid request body")
	}

	if req.Name == "" {
		return httputil.ValidationError(c, "validation failed", map[string]string{
			"name": "required",
		})
	}

	list := models.NewTaskGroup(userID, req.Name)
	list.Icon = req.Icon
	list.Color = req.Color

	// Handle parent list
	if req.ParentID != nil {
		parentID, err := uuid.Parse(*req.ParentID)
		if err != nil {
			return httputil.BadRequest(c, "invalid parent_id")
		}

		// Get parent list to check depth
		var parentDepth int
		err = h.db.QueryRow(c.Context(),
			"SELECT depth FROM task_groups WHERE id = $1 AND user_id = $2 AND deleted_at IS NULL",
			parentID, userID,
		).Scan(&parentDepth)
		if err == pgx.ErrNoRows {
			return httputil.NotFound(c, "parent list")
		}
		if err != nil {
			return httputil.InternalError(c, "database error")
		}

		if err := list.SetParentGroup(parentID, parentDepth); err != nil {
			return httputil.BadRequest(c, err.Error())
		}
	}

	// Insert list
	_, err = h.db.Exec(c.Context(),
		`INSERT INTO task_groups (id, user_id, name, icon, color, parent_id, depth, task_count, created_at, updated_at)
		 VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)`,
		list.ID, list.UserID, list.Name, list.Icon, list.Color, list.ParentID,
		list.Depth, list.TaskCount, list.CreatedAt, list.UpdatedAt,
	)
	if err != nil {
		return httputil.InternalError(c, "failed to create list")
	}

	// Build full path
	fullPath := list.Name
	if list.ParentID != nil {
		var parentName string
		_ = h.db.QueryRow(c.Context(),
			"SELECT name FROM task_groups WHERE id = $1",
			list.ParentID,
		).Scan(&parentName)
		fullPath = parentName + "/" + list.Name
	}

	return httputil.Created(c, ListResponse{
		ID:        list.ID.String(),
		Name:      list.Name,
		Icon:      list.Icon,
		Color:     list.Color,
		ParentID:  func() *string { if req.ParentID != nil { return req.ParentID }; return nil }(),
		Depth:     list.Depth,
		TaskCount: 0,
		FullPath:  fullPath,
		CreatedAt: list.CreatedAt.Format(time.RFC3339),
		UpdatedAt: list.UpdatedAt.Format(time.RFC3339),
	})
}

// GetListTasks returns tasks in a specific list
func (h *TaskHandler) GetListTasks(c *fiber.Ctx) error {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		return httputil.Unauthorized(c, "")
	}

	listID, err := uuid.Parse(c.Params("id"))
	if err != nil {
		return httputil.BadRequest(c, "invalid list ID")
	}

	// Include tasks from sublists option
	includeSublists := c.Query("include_sublists", "false") == "true"

	var rows pgx.Rows
	if includeSublists {
		rows, err = h.db.Query(c.Context(),
			`SELECT t.id, t.title, t.description, t.ai_summary, t.ai_steps, t.status, t.priority,
			 t.due_date, t.completed_at, t.tags, t.parent_id, t.depth, t.complexity,
			 t.group_id, g.name as group_name, t.created_at, t.updated_at,
			 (SELECT COUNT(*) FROM tasks WHERE parent_id = t.id AND deleted_at IS NULL) as children_count
			 FROM tasks t
			 LEFT JOIN task_groups g ON t.group_id = g.id
			 WHERE t.user_id = $1 AND t.deleted_at IS NULL
			 AND (t.group_id = $2 OR t.group_id IN (SELECT id FROM task_groups WHERE parent_id = $2 AND deleted_at IS NULL))
			 ORDER BY t.created_at DESC`,
			userID, listID,
		)
	} else {
		rows, err = h.db.Query(c.Context(),
			`SELECT t.id, t.title, t.description, t.ai_summary, t.ai_steps, t.status, t.priority,
			 t.due_date, t.completed_at, t.tags, t.parent_id, t.depth, t.complexity,
			 t.group_id, g.name as group_name, t.created_at, t.updated_at,
			 (SELECT COUNT(*) FROM tasks WHERE parent_id = t.id AND deleted_at IS NULL) as children_count
			 FROM tasks t
			 LEFT JOIN task_groups g ON t.group_id = g.id
			 WHERE t.user_id = $1 AND t.deleted_at IS NULL AND t.group_id = $2
			 ORDER BY t.created_at DESC`,
			userID, listID,
		)
	}
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

// ArchiveList archives a list and its sublists
func (h *TaskHandler) ArchiveList(c *fiber.Ctx) error {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		return httputil.Unauthorized(c, "")
	}

	listID, err := uuid.Parse(c.Params("id"))
	if err != nil {
		return httputil.BadRequest(c, "invalid list ID")
	}

	now := time.Now()

	// Archive sublists first
	_, _ = h.db.Exec(c.Context(),
		`UPDATE task_groups SET archived = true, archived_at = $1, updated_at = $1
		 WHERE parent_id = $2 AND user_id = $3 AND deleted_at IS NULL`,
		now, listID, userID,
	)

	// Archive the list itself
	result, err := h.db.Exec(c.Context(),
		`UPDATE task_groups SET archived = true, archived_at = $1, updated_at = $1
		 WHERE id = $2 AND user_id = $3 AND deleted_at IS NULL`,
		now, listID, userID,
	)
	if err != nil {
		return httputil.InternalError(c, "failed to archive list")
	}

	if result.RowsAffected() == 0 {
		return httputil.NotFound(c, "list")
	}

	return httputil.Success(c, map[string]string{"status": "archived"})
}

// UnarchiveList restores an archived list and its sublists
func (h *TaskHandler) UnarchiveList(c *fiber.Ctx) error {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		return httputil.Unauthorized(c, "")
	}

	listID, err := uuid.Parse(c.Params("id"))
	if err != nil {
		return httputil.BadRequest(c, "invalid list ID")
	}

	now := time.Now()

	// Unarchive sublists first
	_, _ = h.db.Exec(c.Context(),
		`UPDATE task_groups SET archived = false, archived_at = NULL, updated_at = $1
		 WHERE parent_id = $2 AND user_id = $3 AND deleted_at IS NULL`,
		now, listID, userID,
	)

	// Unarchive the list itself
	result, err := h.db.Exec(c.Context(),
		`UPDATE task_groups SET archived = false, archived_at = NULL, updated_at = $1
		 WHERE id = $2 AND user_id = $3 AND deleted_at IS NULL`,
		now, listID, userID,
	)
	if err != nil {
		return httputil.InternalError(c, "failed to unarchive list")
	}

	if result.RowsAffected() == 0 {
		return httputil.NotFound(c, "list")
	}

	return httputil.Success(c, map[string]string{"status": "unarchived"})
}

// DeleteList deletes a list (and optionally its sublists)
func (h *TaskHandler) DeleteList(c *fiber.Ctx) error {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		return httputil.Unauthorized(c, "")
	}

	listID, err := uuid.Parse(c.Params("id"))
	if err != nil {
		return httputil.BadRequest(c, "invalid list ID")
	}

	// Soft delete the list and its sublists
	now := time.Now()

	// First, unassign tasks from this list and its sublists
	_, _ = h.db.Exec(c.Context(),
		`UPDATE tasks SET group_id = NULL, updated_at = $1
		 WHERE user_id = $2 AND (group_id = $3 OR group_id IN (SELECT id FROM task_groups WHERE parent_id = $3 AND deleted_at IS NULL))`,
		now, userID, listID,
	)

	// Delete sublists first
	_, _ = h.db.Exec(c.Context(),
		`UPDATE task_groups SET deleted_at = $1 WHERE parent_id = $2 AND user_id = $3 AND deleted_at IS NULL`,
		now, listID, userID,
	)

	// Delete the list itself
	result, err := h.db.Exec(c.Context(),
		`UPDATE task_groups SET deleted_at = $1 WHERE id = $2 AND user_id = $3 AND deleted_at IS NULL`,
		now, listID, userID,
	)
	if err != nil {
		return httputil.InternalError(c, "failed to delete list")
	}

	if result.RowsAffected() == 0 {
		return httputil.NotFound(c, "list")
	}

	return httputil.NoContent(c)
}

// CleanupEmptyLists removes lists and sublists with 0 tasks
func (h *TaskHandler) CleanupEmptyLists(c *fiber.Ctx) error {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		return httputil.Unauthorized(c, "")
	}

	now := time.Now()

	// First, recalculate task counts for all lists
	_, err = h.db.Exec(c.Context(),
		`UPDATE task_groups g SET task_count = (
			SELECT COUNT(*) FROM tasks t
			WHERE t.group_id = g.id AND t.deleted_at IS NULL AND t.status != 'completed'
		)
		WHERE g.user_id = $1 AND g.deleted_at IS NULL`,
		userID,
	)
	if err != nil {
		return httputil.InternalError(c, "failed to update task counts")
	}

	// Delete empty sublists first (depth > 0)
	subResult, err := h.db.Exec(c.Context(),
		`UPDATE task_groups SET deleted_at = $1
		 WHERE user_id = $2 AND deleted_at IS NULL
		 AND task_count = 0 AND parent_id IS NOT NULL`,
		now, userID,
	)
	if err != nil {
		return httputil.InternalError(c, "failed to cleanup sublists")
	}
	subDeleted := subResult.RowsAffected()

	// Then delete empty root lists (that don't have sublists)
	rootResult, err := h.db.Exec(c.Context(),
		`UPDATE task_groups SET deleted_at = $1
		 WHERE user_id = $2 AND deleted_at IS NULL
		 AND task_count = 0 AND parent_id IS NULL
		 AND NOT EXISTS (SELECT 1 FROM task_groups sub WHERE sub.parent_id = task_groups.id AND sub.deleted_at IS NULL)`,
		now, userID,
	)
	if err != nil {
		return httputil.InternalError(c, "failed to cleanup root lists")
	}
	rootDeleted := rootResult.RowsAffected()

	return httputil.Success(c, map[string]interface{}{
		"deleted_sublists":   subDeleted,
		"deleted_root_lists": rootDeleted,
		"total_deleted":      subDeleted + rootDeleted,
	})
}

// SearchLists searches lists by name prefix
func (h *TaskHandler) SearchLists(c *fiber.Ctx) error {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		return httputil.Unauthorized(c, "")
	}

	var req struct {
		Query    string  `json:"query"`
		ParentID *string `json:"parent_id,omitempty"`
	}
	if err := c.BodyParser(&req); err != nil {
		return httputil.BadRequest(c, "invalid request body")
	}

	var rows pgx.Rows
	if req.ParentID != nil {
		parentID, err := uuid.Parse(*req.ParentID)
		if err != nil {
			return httputil.BadRequest(c, "invalid parent_id")
		}
		rows, err = h.db.Query(c.Context(),
			`SELECT g.id, g.name, g.icon, g.color, g.parent_id, g.depth, g.task_count,
			 COALESCE(p.name || '/', '') || g.name as full_path,
			 g.created_at, g.updated_at
			 FROM task_groups g
			 LEFT JOIN task_groups p ON g.parent_id = p.id
			 WHERE g.user_id = $1 AND g.deleted_at IS NULL
			 AND g.parent_id = $2 AND g.name ILIKE $3
			 ORDER BY g.name ASC
			 LIMIT 20`,
			userID, parentID, req.Query+"%",
		)
	} else {
		rows, err = h.db.Query(c.Context(),
			`SELECT g.id, g.name, g.icon, g.color, g.parent_id, g.depth, g.task_count,
			 COALESCE(p.name || '/', '') || g.name as full_path,
			 g.created_at, g.updated_at
			 FROM task_groups g
			 LEFT JOIN task_groups p ON g.parent_id = p.id
			 WHERE g.user_id = $1 AND g.deleted_at IS NULL
			 AND g.name ILIKE $2
			 ORDER BY g.name ASC
			 LIMIT 20`,
			userID, req.Query+"%",
		)
	}
	if err != nil {
		return httputil.InternalError(c, "database error")
	}
	defer rows.Close()

	lists := make([]ListResponse, 0)
	for rows.Next() {
		var lr ListResponse
		var id uuid.UUID
		var parentID *uuid.UUID
		var createdAt, updatedAt time.Time

		if err := rows.Scan(&id, &lr.Name, &lr.Icon, &lr.Color, &parentID, &lr.Depth,
			&lr.TaskCount, &lr.FullPath, &createdAt, &updatedAt); err != nil {
			continue
		}

		lr.ID = id.String()
		lr.CreatedAt = createdAt.Format(time.RFC3339)
		lr.UpdatedAt = updatedAt.Format(time.RFC3339)
		if parentID != nil {
			p := parentID.String()
			lr.ParentID = &p
		}
		lists = append(lists, lr)
	}

	return httputil.Success(c, lists)
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

	// Set URL to download endpoint
	attachment.URL = fmt.Sprintf("/api/tasks/%s/attachments/%s/download", taskID.String(), attachment.ID.String())
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
		`SELECT id, task_id, user_id, type, name, url, mime_type, size_bytes, thumbnail_url, metadata, created_at
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

		if err := rows.Scan(&a.ID, &a.TaskID, &a.UserID, &a.Type, &a.Name, &a.URL,
			&a.MimeType, &a.SizeBytes, &a.ThumbnailURL, &metadataJSON, &a.CreatedAt); err != nil {
			continue
		}

		if metadataJSON != nil {
			_ = json.Unmarshal(metadataJSON, &a.Metadata)
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
// Hashtag Parsing Helpers
// =====================================================

var hashtagRegex = regexp.MustCompile(`#([A-Za-z0-9_]+(?:/[A-Za-z0-9_]+)?)`)

// ParseHashtags extracts hashtags from text and returns list paths
func ParseHashtags(text string) []string {
	matches := hashtagRegex.FindAllStringSubmatch(text, -1)
	var results []string
	seen := make(map[string]bool)
	for _, match := range matches {
		if len(match) > 1 {
			path := match[1]
			if !seen[path] {
				results = append(results, path)
				seen[path] = true
			}
		}
	}
	return results
}

// EnsureListsExist creates lists if they don't exist and returns the deepest list ID
func (h *TaskHandler) EnsureListsExist(ctx context.Context, userID uuid.UUID, listPath string) (*uuid.UUID, error) {
	parts := strings.Split(listPath, "/")
	if len(parts) == 0 || parts[0] == "" {
		return nil, nil
	}

	var currentID *uuid.UUID
	var currentDepth int

	for i, part := range parts {
		if part == "" {
			continue
		}

		var listID uuid.UUID
		var depth int

		// Try to find existing list
		var err error
		if currentID == nil {
			err = h.db.QueryRow(ctx,
				`SELECT id, depth FROM task_groups
				 WHERE user_id = $1 AND name = $2 AND parent_id IS NULL AND deleted_at IS NULL`,
				userID, part,
			).Scan(&listID, &depth)
		} else {
			err = h.db.QueryRow(ctx,
				`SELECT id, depth FROM task_groups
				 WHERE user_id = $1 AND name = $2 AND parent_id = $3 AND deleted_at IS NULL`,
				userID, part, currentID,
			).Scan(&listID, &depth)
		}

		if err == pgx.ErrNoRows {
			// Create the list
			list := models.NewTaskGroup(userID, part)
			if currentID != nil {
				if err := list.SetParentGroup(*currentID, currentDepth); err != nil {
					return nil, err
				}
			}
			list.Depth = i
			if list.Depth > 1 {
				list.Depth = 1 // Cap at 1
			}

			_, err = h.db.Exec(ctx,
				`INSERT INTO task_groups (id, user_id, name, icon, color, parent_id, depth, task_count, created_at, updated_at)
				 VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
				 ON CONFLICT (user_id, parent_id, name) DO UPDATE SET updated_at = EXCLUDED.updated_at
				 RETURNING id`,
				list.ID, list.UserID, list.Name, list.Icon, list.Color, list.ParentID,
				list.Depth, list.TaskCount, list.CreatedAt, list.UpdatedAt,
			)
			if err != nil {
				return nil, err
			}

			currentID = &list.ID
			currentDepth = list.Depth
		} else if err != nil {
			return nil, err
		} else {
			currentID = &listID
			currentDepth = depth
		}
	}

	return currentID, nil
}

// ProcessHashtagsForTask extracts hashtags, ensures lists exist, and updates task
func (h *TaskHandler) ProcessHashtagsForTask(ctx context.Context, userID uuid.UUID, task *models.Task) error {
	// Extract from title and description
	text := task.Title
	if task.Description != nil {
		text += " " + *task.Description
	}

	hashtags := ParseHashtags(text)
	if len(hashtags) == 0 {
		return nil
	}

	// Process each hashtag
	var lastListID *uuid.UUID
	for _, path := range hashtags {
		listID, err := h.EnsureListsExist(ctx, userID, path)
		if err != nil {
			continue // Skip on error
		}
		if listID != nil {
			lastListID = listID
			// Add to tags with list: prefix
			tag := "list:" + path
			if !contains(task.Tags, tag) {
				task.Tags = append(task.Tags, tag)
			}
		}
	}

	// Set the group_id to the last list found
	if lastListID != nil {
		task.GroupID = lastListID
	}

	return nil
}

func contains(slice []string, item string) bool {
	for _, s := range slice {
		if s == item {
			return true
		}
	}
	return false
}

// updateListTaskCount recalculates the task count for a specific list
func (h *TaskHandler) updateListTaskCount(ctx context.Context, listID uuid.UUID) {
	_, _ = h.db.Exec(ctx,
		`UPDATE task_groups SET task_count = (
			SELECT COUNT(*) FROM tasks
			WHERE group_id = $1 AND deleted_at IS NULL AND status != 'completed'
		)
		WHERE id = $1`,
		listID,
	)
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

	if result.CleanedTitle != nil {
		updates = append(updates, fmt.Sprintf("title = $%d", argNum))
		args = append(args, *result.CleanedTitle)
		argNum++

		// Store original title
		updates = append(updates, fmt.Sprintf("original_text = (SELECT title FROM tasks WHERE id = $%d)", argNum))
		args = append(args, taskID)
		argNum++

		updates = append(updates, "ai_cleaned_title = true")
	}

	if result.Summary != nil {
		updates = append(updates, fmt.Sprintf("ai_summary = $%d", argNum))
		args = append(args, *result.Summary)
		argNum++
	}

	if result.DueDate != nil {
		updates = append(updates, fmt.Sprintf("due_date = $%d", argNum))
		args = append(args, *result.DueDate)
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
		updates = append(updates, fmt.Sprintf("entities = $%d", argNum))
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
