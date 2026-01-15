package tasks

import (
	"context"
	"encoding/json"
	"fmt"
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
	db  *pgxpool.Pool
	llm *llm.MultiClient
}

// NewTaskHandler creates a new task handler
func NewTaskHandler(db *pgxpool.Pool, llmClient *llm.MultiClient) *TaskHandler {
	return &TaskHandler{
		db:  db,
		llm: llmClient,
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

	// Insert task
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

	// Store original and update
	task.OriginalText = &task.Title
	task.Title = cleaned.Title
	if cleaned.Summary != "" {
		task.AISummary = &cleaned.Summary
	}
	task.AICleanedTitle = true
	task.IncrementVersion()

	_, err = h.db.Exec(c.Context(),
		`UPDATE tasks SET title = $1, ai_summary = $2, original_text = $3, ai_cleaned_title = true,
		 version = $4, updated_at = $5
		 WHERE id = $6 AND user_id = $7`,
		task.Title, task.AISummary, task.OriginalText, task.Version, task.UpdatedAt, taskID, userID,
	)
	if err != nil {
		return httputil.InternalError(c, "failed to update task")
	}

	return httputil.Success(c, toTaskResponse(task, childCount))
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
		 t.due_date, t.completed_at, t.tags, t.parent_id, t.depth, t.complexity,
		 t.group_id, g.name, t.ai_cleaned_title, t.ai_extracted_due, t.ai_decomposed,
		 t.original_text, t.version, t.created_at, t.updated_at,
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
		&task.OriginalText, &task.Version, &task.CreatedAt, &task.UpdatedAt, &childCount,
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
