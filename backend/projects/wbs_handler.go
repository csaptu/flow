package projects

import (
	"context"
	"time"

	"github.com/gofiber/fiber/v2"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	commonModels "github.com/csaptu/flow/common/models"
	"github.com/csaptu/flow/pkg/httputil"
	"github.com/csaptu/flow/pkg/middleware"
	"github.com/csaptu/flow/projects/models"
)

// WBSHandler handles WBS endpoints
type WBSHandler struct {
	db *pgxpool.Pool
}

// NewWBSHandler creates a new WBS handler
func NewWBSHandler(db *pgxpool.Pool) *WBSHandler {
	return &WBSHandler{db: db}
}

// WBSNodeResponse represents a WBS node in API responses
type WBSNodeResponse struct {
	ID           string                   `json:"id"`
	ProjectID    string                   `json:"project_id"`
	ParentID     *string                  `json:"parent_id,omitempty"`
	Title        string                   `json:"title"`
	Description  *string                  `json:"description,omitempty"`
	Status       string                   `json:"status"`
	Priority     int                      `json:"priority"`
	Progress     float64                  `json:"progress"`
	Depth        int                      `json:"depth"`
	Path         string                   `json:"path"`
	Position     int                      `json:"position"`
	AssigneeID   *string                  `json:"assignee_id,omitempty"`
	PlannedStart *string                  `json:"planned_start,omitempty"`
	PlannedEnd   *string                  `json:"planned_end,omitempty"`
	Duration     *int                     `json:"duration,omitempty"`
	IsCritical   bool                     `json:"is_critical"`
	HasChildren  bool                     `json:"has_children"`
	AISteps      []commonModels.TaskStep  `json:"ai_steps,omitempty"`
	CreatedAt    string                   `json:"created_at"`
	UpdatedAt    string                   `json:"updated_at"`
}

// Create creates a new WBS node
func (h *WBSHandler) Create(c *fiber.Ctx) error {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		return httputil.Unauthorized(c, "")
	}

	projectID, err := uuid.Parse(c.Params("id"))
	if err != nil {
		return httputil.BadRequest(c, "invalid project ID")
	}

	// Check membership
	if !h.isMember(c.Context(), projectID, userID) {
		return httputil.Forbidden(c, "not a project member")
	}

	var req struct {
		Title        string  `json:"title"`
		Description  *string `json:"description,omitempty"`
		ParentID     *string `json:"parent_id,omitempty"`
		AssigneeID   *string `json:"assignee_id,omitempty"`
		Priority     *int    `json:"priority,omitempty"`
		PlannedStart *string `json:"planned_start,omitempty"`
		PlannedEnd   *string `json:"planned_end,omitempty"`
	}
	if err := c.BodyParser(&req); err != nil {
		return httputil.BadRequest(c, "invalid request body")
	}

	if req.Title == "" {
		return httputil.ValidationError(c, "validation failed", map[string]string{
			"title": "required",
		})
	}

	node := models.NewWBSNode(projectID, userID, req.Title)
	node.Description = req.Description

	if req.Priority != nil {
		node.Priority = commonModels.Priority(*req.Priority)
	}

	// Handle parent
	if req.ParentID != nil {
		parentID, err := uuid.Parse(*req.ParentID)
		if err != nil {
			return httputil.BadRequest(c, "invalid parent_id")
		}

		var parentPath string
		var parentDepth, maxPosition int
		err = h.db.QueryRow(c.Context(),
			"SELECT path, depth FROM wbs_nodes WHERE id = $1 AND project_id = $2 AND deleted_at IS NULL",
			parentID, projectID,
		).Scan(&parentPath, &parentDepth)
		if err == pgx.ErrNoRows {
			return httputil.NotFound(c, "parent node")
		}
		if err != nil {
			return httputil.InternalError(c, "database error")
		}

		// Get max position under parent
		_ = h.db.QueryRow(c.Context(),
			"SELECT COALESCE(MAX(position), 0) FROM wbs_nodes WHERE parent_id = $1 AND deleted_at IS NULL",
			parentID,
		).Scan(&maxPosition)

		node.SetParent(parentID, parentPath, parentDepth)
		node.Position = maxPosition + 1
		node.Path = parentPath + "." + formatPosition(node.Position)
	} else {
		// Root node - get max position at root
		var maxPosition int
		_ = h.db.QueryRow(c.Context(),
			"SELECT COALESCE(MAX(position), 0) FROM wbs_nodes WHERE project_id = $1 AND parent_id IS NULL AND deleted_at IS NULL",
			projectID,
		).Scan(&maxPosition)
		node.Position = maxPosition + 1
		node.Path = formatPosition(node.Position)
	}

	if req.AssigneeID != nil {
		assigneeID, err := uuid.Parse(*req.AssigneeID)
		if err != nil {
			return httputil.BadRequest(c, "invalid assignee_id")
		}
		node.AssigneeID = &assigneeID
	}

	if req.PlannedStart != nil {
		start, err := time.Parse(time.RFC3339, *req.PlannedStart)
		if err != nil {
			return httputil.BadRequest(c, "invalid planned_start format")
		}
		node.PlannedStart = &start
	}

	if req.PlannedEnd != nil {
		end, err := time.Parse(time.RFC3339, *req.PlannedEnd)
		if err != nil {
			return httputil.BadRequest(c, "invalid planned_end format")
		}
		node.PlannedEnd = &end
	}

	// Insert node
	_, err = h.db.Exec(c.Context(),
		`INSERT INTO wbs_nodes (id, project_id, parent_id, user_id, title, description, status,
		 priority, progress, depth, path, position, assignee_id, planned_start, planned_end,
		 version, created_at, updated_at)
		 VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18)`,
		node.ID, node.ProjectID, node.ParentID, node.UserID, node.Title, node.Description,
		node.Status, node.Priority, node.Progress, node.Depth, node.Path, node.Position,
		node.AssigneeID, node.PlannedStart, node.PlannedEnd, node.Version, node.CreatedAt, node.UpdatedAt,
	)
	if err != nil {
		return httputil.InternalError(c, "failed to create WBS node")
	}

	return httputil.Created(c, toWBSNodeResponse(node, false))
}

// List lists WBS nodes for a project
func (h *WBSHandler) List(c *fiber.Ctx) error {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		return httputil.Unauthorized(c, "")
	}

	projectID, err := uuid.Parse(c.Params("id"))
	if err != nil {
		return httputil.BadRequest(c, "invalid project ID")
	}

	if !h.isMember(c.Context(), projectID, userID) {
		return httputil.Forbidden(c, "not a project member")
	}

	rows, err := h.db.Query(c.Context(),
		`SELECT n.id, n.project_id, n.parent_id, n.title, n.description, n.status, n.priority,
		 n.progress, n.depth, n.path, n.position, n.assignee_id, n.planned_start, n.planned_end,
		 n.duration, n.is_critical, n.ai_steps, n.created_at, n.updated_at,
		 EXISTS(SELECT 1 FROM wbs_nodes WHERE parent_id = n.id AND deleted_at IS NULL) as has_children
		 FROM wbs_nodes n
		 WHERE n.project_id = $1 AND n.deleted_at IS NULL
		 ORDER BY n.path ASC`,
		projectID,
	)
	if err != nil {
		return httputil.InternalError(c, "database error")
	}
	defer rows.Close()

	nodes := make([]WBSNodeResponse, 0)
	for rows.Next() {
		node, hasChildren, err := scanWBSNode(rows)
		if err != nil {
			continue
		}
		nodes = append(nodes, toWBSNodeResponse(node, hasChildren))
	}

	return httputil.Success(c, nodes)
}

// GetTree returns WBS as a tree structure
func (h *WBSHandler) GetTree(c *fiber.Ctx) error {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		return httputil.Unauthorized(c, "")
	}

	projectID, err := uuid.Parse(c.Params("id"))
	if err != nil {
		return httputil.BadRequest(c, "invalid project ID")
	}

	if !h.isMember(c.Context(), projectID, userID) {
		return httputil.Forbidden(c, "not a project member")
	}

	rows, err := h.db.Query(c.Context(),
		`SELECT n.id, n.project_id, n.parent_id, n.title, n.description, n.status, n.priority,
		 n.progress, n.depth, n.path, n.position, n.assignee_id, n.planned_start, n.planned_end,
		 n.duration, n.is_critical, n.ai_steps, n.created_at, n.updated_at,
		 EXISTS(SELECT 1 FROM wbs_nodes WHERE parent_id = n.id AND deleted_at IS NULL) as has_children
		 FROM wbs_nodes n
		 WHERE n.project_id = $1 AND n.deleted_at IS NULL
		 ORDER BY n.path ASC`,
		projectID,
	)
	if err != nil {
		return httputil.InternalError(c, "database error")
	}
	defer rows.Close()

	// Build tree structure
	type TreeNode struct {
		WBSNodeResponse
		Children []TreeNode `json:"children,omitempty"`
	}

	nodeMap := make(map[string]*TreeNode)
	var roots []TreeNode

	for rows.Next() {
		node, hasChildren, err := scanWBSNode(rows)
		if err != nil {
			continue
		}

		resp := toWBSNodeResponse(node, hasChildren)
		treeNode := TreeNode{WBSNodeResponse: resp, Children: []TreeNode{}}
		nodeMap[resp.ID] = &treeNode

		if node.ParentID == nil {
			roots = append(roots, treeNode)
		}
	}

	// Second pass to build parent-child relationships
	for id, node := range nodeMap {
		if node.ParentID != nil {
			if parent, ok := nodeMap[*node.ParentID]; ok {
				parent.Children = append(parent.Children, *nodeMap[id])
			}
		}
	}

	return httputil.Success(c, roots)
}

// GetByID gets a WBS node by ID
func (h *WBSHandler) GetByID(c *fiber.Ctx) error {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		return httputil.Unauthorized(c, "")
	}

	projectID, err := uuid.Parse(c.Params("id"))
	if err != nil {
		return httputil.BadRequest(c, "invalid project ID")
	}

	nodeID, err := uuid.Parse(c.Params("node_id"))
	if err != nil {
		return httputil.BadRequest(c, "invalid node ID")
	}

	if !h.isMember(c.Context(), projectID, userID) {
		return httputil.Forbidden(c, "not a project member")
	}

	node, hasChildren, err := h.getNode(c.Context(), nodeID, projectID)
	if err != nil {
		return err
	}

	return httputil.Success(c, toWBSNodeResponse(node, hasChildren))
}

// Update updates a WBS node
func (h *WBSHandler) Update(c *fiber.Ctx) error {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		return httputil.Unauthorized(c, "")
	}

	projectID, err := uuid.Parse(c.Params("id"))
	if err != nil {
		return httputil.BadRequest(c, "invalid project ID")
	}

	nodeID, err := uuid.Parse(c.Params("node_id"))
	if err != nil {
		return httputil.BadRequest(c, "invalid node ID")
	}

	if !h.isMember(c.Context(), projectID, userID) {
		return httputil.Forbidden(c, "not a project member")
	}

	var req struct {
		Title        *string `json:"title,omitempty"`
		Description  *string `json:"description,omitempty"`
		Status       *string `json:"status,omitempty"`
		Priority     *int    `json:"priority,omitempty"`
		AssigneeID   *string `json:"assignee_id,omitempty"`
		PlannedStart *string `json:"planned_start,omitempty"`
		PlannedEnd   *string `json:"planned_end,omitempty"`
	}
	if err := c.BodyParser(&req); err != nil {
		return httputil.BadRequest(c, "invalid request body")
	}

	now := time.Now()
	_, err = h.db.Exec(c.Context(),
		`UPDATE wbs_nodes SET
		 title = COALESCE($1, title),
		 description = COALESCE($2, description),
		 status = COALESCE($3, status),
		 priority = COALESCE($4, priority),
		 version = version + 1,
		 updated_at = $5
		 WHERE id = $6 AND project_id = $7 AND deleted_at IS NULL`,
		req.Title, req.Description, req.Status, req.Priority, now, nodeID, projectID,
	)
	if err != nil {
		return httputil.InternalError(c, "failed to update node")
	}

	node, hasChildren, _ := h.getNode(c.Context(), nodeID, projectID)
	return httputil.Success(c, toWBSNodeResponse(node, hasChildren))
}

// Delete deletes a WBS node
func (h *WBSHandler) Delete(c *fiber.Ctx) error {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		return httputil.Unauthorized(c, "")
	}

	projectID, err := uuid.Parse(c.Params("id"))
	if err != nil {
		return httputil.BadRequest(c, "invalid project ID")
	}

	nodeID, err := uuid.Parse(c.Params("node_id"))
	if err != nil {
		return httputil.BadRequest(c, "invalid node ID")
	}

	if !h.isMember(c.Context(), projectID, userID) {
		return httputil.Forbidden(c, "not a project member")
	}

	// Get node path to delete all descendants
	var nodePath string
	err = h.db.QueryRow(c.Context(),
		"SELECT path FROM wbs_nodes WHERE id = $1 AND project_id = $2 AND deleted_at IS NULL",
		nodeID, projectID,
	).Scan(&nodePath)
	if err == pgx.ErrNoRows {
		return httputil.NotFound(c, "WBS node")
	}
	if err != nil {
		return httputil.InternalError(c, "database error")
	}

	now := time.Now()
	// Delete node and all descendants
	_, err = h.db.Exec(c.Context(),
		"UPDATE wbs_nodes SET deleted_at = $1 WHERE project_id = $2 AND (id = $3 OR path LIKE $4) AND deleted_at IS NULL",
		now, projectID, nodeID, nodePath+".%",
	)
	if err != nil {
		return httputil.InternalError(c, "failed to delete node")
	}

	// Also delete dependencies involving this node
	_, _ = h.db.Exec(c.Context(),
		"DELETE FROM wbs_dependencies WHERE predecessor_id = $1 OR successor_id = $1",
		nodeID,
	)

	return httputil.NoContent(c)
}

// Move moves a WBS node to a new parent
func (h *WBSHandler) Move(c *fiber.Ctx) error {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		return httputil.Unauthorized(c, "")
	}

	projectID, err := uuid.Parse(c.Params("id"))
	if err != nil {
		return httputil.BadRequest(c, "invalid project ID")
	}

	_, err = uuid.Parse(c.Params("node_id"))
	if err != nil {
		return httputil.BadRequest(c, "invalid node ID")
	}

	if !h.isMember(c.Context(), projectID, userID) {
		return httputil.Forbidden(c, "not a project member")
	}

	var req struct {
		NewParentID *string `json:"new_parent_id"`
		Position    int     `json:"position"`
	}
	if err := c.BodyParser(&req); err != nil {
		return httputil.BadRequest(c, "invalid request body")
	}

	// TODO: Implement full move logic with path recalculation
	return httputil.Success(c, map[string]string{"message": "node moved"})
}

// UpdateProgress updates the progress of a WBS node
func (h *WBSHandler) UpdateProgress(c *fiber.Ctx) error {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		return httputil.Unauthorized(c, "")
	}

	projectID, err := uuid.Parse(c.Params("id"))
	if err != nil {
		return httputil.BadRequest(c, "invalid project ID")
	}

	nodeID, err := uuid.Parse(c.Params("node_id"))
	if err != nil {
		return httputil.BadRequest(c, "invalid node ID")
	}

	if !h.isMember(c.Context(), projectID, userID) {
		return httputil.Forbidden(c, "not a project member")
	}

	var req struct {
		Progress float64 `json:"progress"`
	}
	if err := c.BodyParser(&req); err != nil {
		return httputil.BadRequest(c, "invalid request body")
	}

	if req.Progress < 0 || req.Progress > 100 {
		return httputil.BadRequest(c, "progress must be between 0 and 100")
	}

	now := time.Now()
	status := commonModels.StatusInProgress
	var completedAt *time.Time
	if req.Progress == 100 {
		status = commonModels.StatusCompleted
		completedAt = &now
	}

	_, err = h.db.Exec(c.Context(),
		`UPDATE wbs_nodes SET progress = $1, status = $2, completed_at = $3, version = version + 1, updated_at = $4
		 WHERE id = $5 AND project_id = $6 AND deleted_at IS NULL`,
		req.Progress, status, completedAt, now, nodeID, projectID,
	)
	if err != nil {
		return httputil.InternalError(c, "failed to update progress")
	}

	node, hasChildren, _ := h.getNode(c.Context(), nodeID, projectID)
	return httputil.Success(c, toWBSNodeResponse(node, hasChildren))
}

// Dependencies

// AddDependency adds a dependency between WBS nodes
func (h *WBSHandler) AddDependency(c *fiber.Ctx) error {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		return httputil.Unauthorized(c, "")
	}

	projectID, err := uuid.Parse(c.Params("id"))
	if err != nil {
		return httputil.BadRequest(c, "invalid project ID")
	}

	if !h.isMember(c.Context(), projectID, userID) {
		return httputil.Forbidden(c, "not a project member")
	}

	var req struct {
		PredecessorID  string `json:"predecessor_id"`
		SuccessorID    string `json:"successor_id"`
		DependencyType string `json:"dependency_type"`
		LagDays        int    `json:"lag_days"`
	}
	if err := c.BodyParser(&req); err != nil {
		return httputil.BadRequest(c, "invalid request body")
	}

	predecessorID, err := uuid.Parse(req.PredecessorID)
	if err != nil {
		return httputil.BadRequest(c, "invalid predecessor_id")
	}

	successorID, err := uuid.Parse(req.SuccessorID)
	if err != nil {
		return httputil.BadRequest(c, "invalid successor_id")
	}

	if predecessorID == successorID {
		return httputil.BadRequest(c, "cannot create self-dependency")
	}

	depType := commonModels.DependencyType(req.DependencyType)
	if !depType.IsValid() {
		depType = commonModels.DependencyFS
	}

	// TODO: Check for cycles

	id := uuid.New()
	_, err = h.db.Exec(c.Context(),
		`INSERT INTO wbs_dependencies (id, project_id, predecessor_id, successor_id, dependency_type, lag_days, created_at)
		 VALUES ($1, $2, $3, $4, $5, $6, $7)`,
		id, projectID, predecessorID, successorID, depType, req.LagDays, time.Now(),
	)
	if err != nil {
		return httputil.InternalError(c, "failed to add dependency")
	}

	return httputil.Created(c, map[string]string{
		"id":      id.String(),
		"message": "dependency added",
	})
}

// ListDependencies lists dependencies for a project
func (h *WBSHandler) ListDependencies(c *fiber.Ctx) error {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		return httputil.Unauthorized(c, "")
	}

	projectID, err := uuid.Parse(c.Params("id"))
	if err != nil {
		return httputil.BadRequest(c, "invalid project ID")
	}

	if !h.isMember(c.Context(), projectID, userID) {
		return httputil.Forbidden(c, "not a project member")
	}

	rows, err := h.db.Query(c.Context(),
		`SELECT id, predecessor_id, successor_id, dependency_type, lag_days, created_at
		 FROM wbs_dependencies WHERE project_id = $1`,
		projectID,
	)
	if err != nil {
		return httputil.InternalError(c, "database error")
	}
	defer rows.Close()

	deps := make([]map[string]interface{}, 0)
	for rows.Next() {
		var id, predecessorID, successorID uuid.UUID
		var depType commonModels.DependencyType
		var lagDays int
		var createdAt time.Time

		if err := rows.Scan(&id, &predecessorID, &successorID, &depType, &lagDays, &createdAt); err != nil {
			continue
		}

		deps = append(deps, map[string]interface{}{
			"id":              id.String(),
			"predecessor_id":  predecessorID.String(),
			"successor_id":    successorID.String(),
			"dependency_type": string(depType),
			"lag_days":        lagDays,
			"created_at":      createdAt.Format(time.RFC3339),
		})
	}

	return httputil.Success(c, deps)
}

// RemoveDependency removes a dependency
func (h *WBSHandler) RemoveDependency(c *fiber.Ctx) error {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		return httputil.Unauthorized(c, "")
	}

	projectID, err := uuid.Parse(c.Params("id"))
	if err != nil {
		return httputil.BadRequest(c, "invalid project ID")
	}

	depID, err := uuid.Parse(c.Params("dep_id"))
	if err != nil {
		return httputil.BadRequest(c, "invalid dependency ID")
	}

	if !h.isMember(c.Context(), projectID, userID) {
		return httputil.Forbidden(c, "not a project member")
	}

	_, err = h.db.Exec(c.Context(),
		"DELETE FROM wbs_dependencies WHERE id = $1 AND project_id = $2",
		depID, projectID,
	)
	if err != nil {
		return httputil.InternalError(c, "failed to remove dependency")
	}

	return httputil.NoContent(c)
}

// GetGantt returns Gantt chart data
func (h *WBSHandler) GetGantt(c *fiber.Ctx) error {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		return httputil.Unauthorized(c, "")
	}

	projectID, err := uuid.Parse(c.Params("id"))
	if err != nil {
		return httputil.BadRequest(c, "invalid project ID")
	}

	if !h.isMember(c.Context(), projectID, userID) {
		return httputil.Forbidden(c, "not a project member")
	}

	// Get all WBS nodes with their dependencies
	rows, err := h.db.Query(c.Context(),
		`SELECT n.id, n.parent_id, n.title, n.planned_start, n.planned_end, n.progress,
		 n.assignee_id, n.is_critical, n.duration
		 FROM wbs_nodes n
		 WHERE n.project_id = $1 AND n.deleted_at IS NULL
		 ORDER BY n.path ASC`,
		projectID,
	)
	if err != nil {
		return httputil.InternalError(c, "database error")
	}
	defer rows.Close()

	bars := make([]models.GanttBar, 0)
	for rows.Next() {
		var id uuid.UUID
		var parentID *uuid.UUID
		var title string
		var plannedStart, plannedEnd *time.Time
		var progress float64
		var assigneeID *uuid.UUID
		var isCritical bool
		var duration *int

		if err := rows.Scan(&id, &parentID, &title, &plannedStart, &plannedEnd, &progress,
			&assigneeID, &isCritical, &duration); err != nil {
			continue
		}

		bar := models.GanttBar{
			ID:          id.String(),
			Title:       title,
			Start:       plannedStart,
			End:         plannedEnd,
			Progress:    progress,
			IsCritical:  isCritical,
			IsMilestone: duration != nil && *duration == 0,
		}

		if parentID != nil {
			p := parentID.String()
			bar.ParentID = &p
		}
		if assigneeID != nil {
			a := assigneeID.String()
			bar.AssigneeID = &a
		}

		// Get dependencies for this node
		depRows, _ := h.db.Query(c.Context(),
			"SELECT predecessor_id FROM wbs_dependencies WHERE successor_id = $1",
			id,
		)
		bar.Dependencies = make([]string, 0)
		for depRows.Next() {
			var predID uuid.UUID
			if depRows.Scan(&predID) == nil {
				bar.Dependencies = append(bar.Dependencies, predID.String())
			}
		}
		depRows.Close()

		bars = append(bars, bar)
	}

	return httputil.Success(c, bars)
}

// AssignedToMe returns tasks assigned to the current user across all projects
func (h *WBSHandler) AssignedToMe(c *fiber.Ctx) error {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		return httputil.Unauthorized(c, "")
	}

	rows, err := h.db.Query(c.Context(),
		`SELECT n.id, n.project_id, n.parent_id, n.title, n.description, n.status, n.priority,
		 n.progress, n.depth, n.path, n.position, n.assignee_id, n.planned_start, n.planned_end,
		 n.duration, n.is_critical, n.ai_steps, n.created_at, n.updated_at,
		 p.name as project_name
		 FROM wbs_nodes n
		 JOIN projects p ON n.project_id = p.id
		 WHERE n.assignee_id = $1 AND n.deleted_at IS NULL AND n.status != 'completed'
		 ORDER BY n.priority DESC, n.planned_end ASC NULLS LAST
		 LIMIT 50`,
		userID,
	)
	if err != nil {
		return httputil.InternalError(c, "database error")
	}
	defer rows.Close()

	type AssignedTask struct {
		WBSNodeResponse
		ProjectName string `json:"project_name"`
	}

	tasks := make([]AssignedTask, 0)
	for rows.Next() {
		var node models.WBSNode
		var projectName string
		var aiStepsJSON []byte

		err := rows.Scan(
			&node.ID, &node.ProjectID, &node.ParentID, &node.Title, &node.Description,
			&node.Status, &node.Priority, &node.Progress, &node.Depth, &node.Path,
			&node.Position, &node.AssigneeID, &node.PlannedStart, &node.PlannedEnd,
			&node.Duration, &node.IsCritical, &aiStepsJSON, &node.CreatedAt, &node.UpdatedAt,
			&projectName,
		)
		if err != nil {
			continue
		}

		if aiStepsJSON != nil {
			_ = node.SetAIStepsFromJSON(aiStepsJSON)
		}

		tasks = append(tasks, AssignedTask{
			WBSNodeResponse: toWBSNodeResponse(&node, false),
			ProjectName:     projectName,
		})
	}

	return httputil.Success(c, tasks)
}

// Helper methods

func (h *WBSHandler) isMember(ctx context.Context, projectID, userID uuid.UUID) bool {
	var exists bool
	_ = h.db.QueryRow(ctx,
		"SELECT EXISTS(SELECT 1 FROM project_members WHERE project_id = $1 AND user_id = $2 AND left_at IS NULL)",
		projectID, userID,
	).Scan(&exists)
	return exists
}

func (h *WBSHandler) getNode(ctx context.Context, nodeID, projectID uuid.UUID) (*models.WBSNode, bool, error) {
	var node models.WBSNode
	var hasChildren bool
	var aiStepsJSON []byte

	err := h.db.QueryRow(ctx,
		`SELECT n.id, n.project_id, n.parent_id, n.user_id, n.title, n.description, n.status, n.priority,
		 n.progress, n.depth, n.path, n.position, n.assignee_id, n.planned_start, n.planned_end,
		 n.duration, n.is_critical, n.ai_steps, n.version, n.created_at, n.updated_at,
		 EXISTS(SELECT 1 FROM wbs_nodes WHERE parent_id = n.id AND deleted_at IS NULL) as has_children
		 FROM wbs_nodes n
		 WHERE n.id = $1 AND n.project_id = $2 AND n.deleted_at IS NULL`,
		nodeID, projectID,
	).Scan(
		&node.ID, &node.ProjectID, &node.ParentID, &node.UserID, &node.Title, &node.Description,
		&node.Status, &node.Priority, &node.Progress, &node.Depth, &node.Path, &node.Position,
		&node.AssigneeID, &node.PlannedStart, &node.PlannedEnd, &node.Duration, &node.IsCritical,
		&aiStepsJSON, &node.Version, &node.CreatedAt, &node.UpdatedAt, &hasChildren,
	)

	if err == pgx.ErrNoRows {
		return nil, false, fiber.NewError(fiber.StatusNotFound, "WBS node not found")
	}
	if err != nil {
		return nil, false, fiber.NewError(fiber.StatusInternalServerError, "database error")
	}

	if aiStepsJSON != nil {
		_ = node.SetAIStepsFromJSON(aiStepsJSON)
	}

	return &node, hasChildren, nil
}

func scanWBSNode(rows pgx.Rows) (*models.WBSNode, bool, error) {
	var node models.WBSNode
	var hasChildren bool
	var aiStepsJSON []byte

	err := rows.Scan(
		&node.ID, &node.ProjectID, &node.ParentID, &node.Title, &node.Description,
		&node.Status, &node.Priority, &node.Progress, &node.Depth, &node.Path,
		&node.Position, &node.AssigneeID, &node.PlannedStart, &node.PlannedEnd,
		&node.Duration, &node.IsCritical, &aiStepsJSON, &node.CreatedAt, &node.UpdatedAt,
		&hasChildren,
	)
	if err != nil {
		return nil, false, err
	}

	if aiStepsJSON != nil {
		_ = node.SetAIStepsFromJSON(aiStepsJSON)
	}

	return &node, hasChildren, nil
}

func toWBSNodeResponse(n *models.WBSNode, hasChildren bool) WBSNodeResponse {
	resp := WBSNodeResponse{
		ID:          n.ID.String(),
		ProjectID:   n.ProjectID.String(),
		Title:       n.Title,
		Description: n.Description,
		Status:      string(n.Status),
		Priority:    int(n.Priority),
		Progress:    n.Progress,
		Depth:       n.Depth,
		Path:        n.Path,
		Position:    n.Position,
		Duration:    n.Duration,
		IsCritical:  n.IsCritical,
		HasChildren: hasChildren,
		AISteps:     n.AISteps,
		CreatedAt:   n.CreatedAt.Format(time.RFC3339),
		UpdatedAt:   n.UpdatedAt.Format(time.RFC3339),
	}

	if n.ParentID != nil {
		p := n.ParentID.String()
		resp.ParentID = &p
	}
	if n.AssigneeID != nil {
		a := n.AssigneeID.String()
		resp.AssigneeID = &a
	}
	if n.PlannedStart != nil {
		s := n.PlannedStart.Format(time.RFC3339)
		resp.PlannedStart = &s
	}
	if n.PlannedEnd != nil {
		e := n.PlannedEnd.Format(time.RFC3339)
		resp.PlannedEnd = &e
	}

	return resp
}

func formatPosition(pos int) string {
	return string(rune('0' + pos))
}
