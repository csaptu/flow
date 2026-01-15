package projects

import (
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

// ProjectHandler handles project endpoints
type ProjectHandler struct {
	db *pgxpool.Pool
}

// NewProjectHandler creates a new project handler
func NewProjectHandler(db *pgxpool.Pool) *ProjectHandler {
	return &ProjectHandler{db: db}
}

// CreateProjectRequest represents the project creation request
type CreateProjectRequest struct {
	Name        string  `json:"name"`
	Description *string `json:"description,omitempty"`
	Methodology *string `json:"methodology,omitempty"`
	Color       *string `json:"color,omitempty"`
	Icon        *string `json:"icon,omitempty"`
	StartDate   *string `json:"start_date,omitempty"`
	TargetDate  *string `json:"target_date,omitempty"`
}

// ProjectResponse represents a project in API responses
type ProjectResponse struct {
	ID          string                      `json:"id"`
	Name        string                      `json:"name"`
	Description *string                     `json:"description,omitempty"`
	Status      string                      `json:"status"`
	Methodology string                      `json:"methodology"`
	Color       *string                     `json:"color,omitempty"`
	Icon        *string                     `json:"icon,omitempty"`
	StartDate   *string                     `json:"start_date,omitempty"`
	TargetDate  *string                     `json:"target_date,omitempty"`
	OwnerID     string                      `json:"owner_id"`
	Progress    models.ProjectProgress      `json:"progress"`
	MemberCount int                         `json:"member_count"`
	CreatedAt   string                      `json:"created_at"`
	UpdatedAt   string                      `json:"updated_at"`
}

// Create handles project creation
func (h *ProjectHandler) Create(c *fiber.Ctx) error {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		return httputil.Unauthorized(c, "")
	}

	var req CreateProjectRequest
	if err := c.BodyParser(&req); err != nil {
		return httputil.BadRequest(c, "invalid request body")
	}

	if req.Name == "" {
		return httputil.ValidationError(c, "validation failed", map[string]string{
			"name": "required",
		})
	}

	project := models.NewProject(req.Name, userID)
	project.Description = req.Description
	project.Color = req.Color
	project.Icon = req.Icon

	if req.Methodology != nil {
		project.Methodology = commonModels.Methodology(*req.Methodology)
	}
	if req.StartDate != nil {
		startDate, err := time.Parse(time.RFC3339, *req.StartDate)
		if err != nil {
			return httputil.BadRequest(c, "invalid start_date format")
		}
		project.StartDate = &startDate
	}
	if req.TargetDate != nil {
		targetDate, err := time.Parse(time.RFC3339, *req.TargetDate)
		if err != nil {
			return httputil.BadRequest(c, "invalid target_date format")
		}
		project.TargetDate = &targetDate
	}

	// Start transaction
	tx, err := h.db.Begin(c.Context())
	if err != nil {
		return httputil.InternalError(c, "database error")
	}
	defer tx.Rollback(c.Context())

	// Insert project
	_, err = tx.Exec(c.Context(),
		`INSERT INTO projects (id, name, description, status, methodology, color, icon,
		 start_date, target_date, owner_id, created_at, updated_at)
		 VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)`,
		project.ID, project.Name, project.Description, project.Status, project.Methodology,
		project.Color, project.Icon, project.StartDate, project.TargetDate,
		project.OwnerID, project.CreatedAt, project.UpdatedAt,
	)
	if err != nil {
		return httputil.InternalError(c, "failed to create project")
	}

	// Add owner as project member
	_, err = tx.Exec(c.Context(),
		`INSERT INTO project_members (id, project_id, user_id, role, joined_at)
		 VALUES ($1, $2, $3, $4, $5)`,
		uuid.New(), project.ID, userID, commonModels.MemberRoleOwner, time.Now(),
	)
	if err != nil {
		return httputil.InternalError(c, "failed to add owner as member")
	}

	if err := tx.Commit(c.Context()); err != nil {
		return httputil.InternalError(c, "failed to commit transaction")
	}

	return httputil.Created(c, toProjectResponse(project, 1, models.ProjectProgress{}))
}

// List handles listing projects for a user
func (h *ProjectHandler) List(c *fiber.Ctx) error {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		return httputil.Unauthorized(c, "")
	}

	pagination := httputil.ParsePagination(c)

	rows, err := h.db.Query(c.Context(),
		`SELECT p.id, p.name, p.description, p.status, p.methodology, p.color, p.icon,
		 p.start_date, p.target_date, p.owner_id, p.created_at, p.updated_at,
		 (SELECT COUNT(*) FROM project_members WHERE project_id = p.id AND left_at IS NULL) as member_count,
		 (SELECT COUNT(*) FROM wbs_nodes WHERE project_id = p.id AND deleted_at IS NULL) as total_nodes,
		 (SELECT COUNT(*) FROM wbs_nodes WHERE project_id = p.id AND status = 'completed' AND deleted_at IS NULL) as completed_nodes
		 FROM projects p
		 JOIN project_members pm ON p.id = pm.project_id
		 WHERE pm.user_id = $1 AND pm.left_at IS NULL AND p.deleted_at IS NULL
		 ORDER BY p.updated_at DESC
		 LIMIT $2 OFFSET $3`,
		userID, pagination.PageSize, pagination.Offset(),
	)
	if err != nil {
		return httputil.InternalError(c, "database error")
	}
	defer rows.Close()

	projects := make([]ProjectResponse, 0)
	for rows.Next() {
		var p models.Project
		var memberCount, totalNodes, completedNodes int

		err := rows.Scan(
			&p.ID, &p.Name, &p.Description, &p.Status, &p.Methodology, &p.Color, &p.Icon,
			&p.StartDate, &p.TargetDate, &p.OwnerID, &p.CreatedAt, &p.UpdatedAt,
			&memberCount, &totalNodes, &completedNodes,
		)
		if err != nil {
			continue
		}

		progress := p.CalculateProgress(totalNodes, completedNodes)
		projects = append(projects, toProjectResponse(&p, memberCount, progress))
	}

	// Get total count
	var totalCount int64
	_ = h.db.QueryRow(c.Context(),
		`SELECT COUNT(*) FROM projects p
		 JOIN project_members pm ON p.id = pm.project_id
		 WHERE pm.user_id = $1 AND pm.left_at IS NULL AND p.deleted_at IS NULL`,
		userID,
	).Scan(&totalCount)

	return httputil.SuccessWithMeta(c, projects, httputil.BuildMeta(pagination.Page, pagination.PageSize, totalCount))
}

// GetByID handles getting a project by ID
func (h *ProjectHandler) GetByID(c *fiber.Ctx) error {
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

	var p models.Project
	var memberCount, totalNodes, completedNodes int

	err = h.db.QueryRow(c.Context(),
		`SELECT p.id, p.name, p.description, p.status, p.methodology, p.color, p.icon,
		 p.start_date, p.target_date, p.owner_id, p.created_at, p.updated_at,
		 (SELECT COUNT(*) FROM project_members WHERE project_id = p.id AND left_at IS NULL) as member_count,
		 (SELECT COUNT(*) FROM wbs_nodes WHERE project_id = p.id AND deleted_at IS NULL) as total_nodes,
		 (SELECT COUNT(*) FROM wbs_nodes WHERE project_id = p.id AND status = 'completed' AND deleted_at IS NULL) as completed_nodes
		 FROM projects p WHERE p.id = $1 AND p.deleted_at IS NULL`,
		projectID,
	).Scan(
		&p.ID, &p.Name, &p.Description, &p.Status, &p.Methodology, &p.Color, &p.Icon,
		&p.StartDate, &p.TargetDate, &p.OwnerID, &p.CreatedAt, &p.UpdatedAt,
		&memberCount, &totalNodes, &completedNodes,
	)

	if err == pgx.ErrNoRows {
		return httputil.NotFound(c, "project")
	}
	if err != nil {
		return httputil.InternalError(c, "database error")
	}

	progress := p.CalculateProgress(totalNodes, completedNodes)
	return httputil.Success(c, toProjectResponse(&p, memberCount, progress))
}

// Update handles updating a project
func (h *ProjectHandler) Update(c *fiber.Ctx) error {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		return httputil.Unauthorized(c, "")
	}

	projectID, err := uuid.Parse(c.Params("id"))
	if err != nil {
		return httputil.BadRequest(c, "invalid project ID")
	}

	// Check if user has admin/owner role
	if !h.canManage(c.Context(), projectID, userID) {
		return httputil.Forbidden(c, "insufficient permissions")
	}

	var req struct {
		Name        *string `json:"name,omitempty"`
		Description *string `json:"description,omitempty"`
		Status      *string `json:"status,omitempty"`
		Methodology *string `json:"methodology,omitempty"`
		Color       *string `json:"color,omitempty"`
		Icon        *string `json:"icon,omitempty"`
		StartDate   *string `json:"start_date,omitempty"`
		TargetDate  *string `json:"target_date,omitempty"`
	}
	if err := c.BodyParser(&req); err != nil {
		return httputil.BadRequest(c, "invalid request body")
	}

	// Build update
	now := time.Now()
	_, err = h.db.Exec(c.Context(),
		`UPDATE projects SET
		 name = COALESCE($1, name),
		 description = COALESCE($2, description),
		 status = COALESCE($3, status),
		 methodology = COALESCE($4, methodology),
		 color = COALESCE($5, color),
		 icon = COALESCE($6, icon),
		 updated_at = $7
		 WHERE id = $8 AND deleted_at IS NULL`,
		req.Name, req.Description, req.Status, req.Methodology, req.Color, req.Icon, now, projectID,
	)
	if err != nil {
		return httputil.InternalError(c, "failed to update project")
	}

	// Return updated project
	return h.GetByID(c)
}

// Delete handles deleting a project
func (h *ProjectHandler) Delete(c *fiber.Ctx) error {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		return httputil.Unauthorized(c, "")
	}

	projectID, err := uuid.Parse(c.Params("id"))
	if err != nil {
		return httputil.BadRequest(c, "invalid project ID")
	}

	// Only owner can delete
	var ownerID uuid.UUID
	err = h.db.QueryRow(c.Context(),
		"SELECT owner_id FROM projects WHERE id = $1 AND deleted_at IS NULL",
		projectID,
	).Scan(&ownerID)

	if err == pgx.ErrNoRows {
		return httputil.NotFound(c, "project")
	}
	if err != nil {
		return httputil.InternalError(c, "database error")
	}

	if ownerID != userID {
		return httputil.Forbidden(c, "only owner can delete project")
	}

	// Soft delete project and all WBS nodes
	now := time.Now()
	_, err = h.db.Exec(c.Context(),
		"UPDATE projects SET deleted_at = $1 WHERE id = $2",
		now, projectID,
	)
	if err != nil {
		return httputil.InternalError(c, "failed to delete project")
	}

	_, _ = h.db.Exec(c.Context(),
		"UPDATE wbs_nodes SET deleted_at = $1 WHERE project_id = $2",
		now, projectID,
	)

	return httputil.NoContent(c)
}

// Team management endpoints

// ListMembers lists project members
func (h *ProjectHandler) ListMembers(c *fiber.Ctx) error {
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
		`SELECT pm.id, pm.user_id, pm.role, pm.joined_at, u.name, u.email, u.avatar_url
		 FROM project_members pm
		 JOIN users u ON pm.user_id = u.id
		 WHERE pm.project_id = $1 AND pm.left_at IS NULL
		 ORDER BY pm.joined_at ASC`,
		projectID,
	)
	if err != nil {
		return httputil.InternalError(c, "database error")
	}
	defer rows.Close()

	members := make([]map[string]interface{}, 0)
	for rows.Next() {
		var id, memberUserID uuid.UUID
		var role commonModels.MemberRole
		var joinedAt time.Time
		var name, email string
		var avatarURL *string

		if err := rows.Scan(&id, &memberUserID, &role, &joinedAt, &name, &email, &avatarURL); err != nil {
			continue
		}

		members = append(members, map[string]interface{}{
			"id":         id.String(),
			"user_id":    memberUserID.String(),
			"role":       string(role),
			"joined_at":  joinedAt.Format(time.RFC3339),
			"name":       name,
			"email":      email,
			"avatar_url": avatarURL,
		})
	}

	return httputil.Success(c, members)
}

// AddMember adds a member to project
func (h *ProjectHandler) AddMember(c *fiber.Ctx) error {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		return httputil.Unauthorized(c, "")
	}

	projectID, err := uuid.Parse(c.Params("id"))
	if err != nil {
		return httputil.BadRequest(c, "invalid project ID")
	}

	if !h.canManage(c.Context(), projectID, userID) {
		return httputil.Forbidden(c, "insufficient permissions")
	}

	var req struct {
		UserID string `json:"user_id"`
		Role   string `json:"role"`
	}
	if err := c.BodyParser(&req); err != nil {
		return httputil.BadRequest(c, "invalid request body")
	}

	newMemberID, err := uuid.Parse(req.UserID)
	if err != nil {
		return httputil.BadRequest(c, "invalid user_id")
	}

	// Check if already a member
	var exists bool
	_ = h.db.QueryRow(c.Context(),
		"SELECT EXISTS(SELECT 1 FROM project_members WHERE project_id = $1 AND user_id = $2 AND left_at IS NULL)",
		projectID, newMemberID,
	).Scan(&exists)
	if exists {
		return httputil.Conflict(c, "user is already a member")
	}

	id := uuid.New()
	now := time.Now()
	role := commonModels.MemberRole(req.Role)
	if !role.IsValid() {
		role = commonModels.MemberRoleMember
	}

	_, err = h.db.Exec(c.Context(),
		`INSERT INTO project_members (id, project_id, user_id, role, joined_at)
		 VALUES ($1, $2, $3, $4, $5)`,
		id, projectID, newMemberID, role, now,
	)
	if err != nil {
		return httputil.InternalError(c, "failed to add member")
	}

	return httputil.Created(c, map[string]string{
		"id":      id.String(),
		"message": "member added",
	})
}

// UpdateMember updates a member's role
func (h *ProjectHandler) UpdateMember(c *fiber.Ctx) error {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		return httputil.Unauthorized(c, "")
	}

	projectID, err := uuid.Parse(c.Params("id"))
	if err != nil {
		return httputil.BadRequest(c, "invalid project ID")
	}

	memberID, err := uuid.Parse(c.Params("member_id"))
	if err != nil {
		return httputil.BadRequest(c, "invalid member ID")
	}

	if !h.canManage(c.Context(), projectID, userID) {
		return httputil.Forbidden(c, "insufficient permissions")
	}

	var req struct {
		Role string `json:"role"`
	}
	if err := c.BodyParser(&req); err != nil {
		return httputil.BadRequest(c, "invalid request body")
	}

	role := commonModels.MemberRole(req.Role)
	if !role.IsValid() {
		return httputil.BadRequest(c, "invalid role")
	}

	// Can't change owner role
	if role == commonModels.MemberRoleOwner {
		return httputil.BadRequest(c, "cannot assign owner role")
	}

	_, err = h.db.Exec(c.Context(),
		"UPDATE project_members SET role = $1 WHERE id = $2 AND project_id = $3 AND left_at IS NULL",
		role, memberID, projectID,
	)
	if err != nil {
		return httputil.InternalError(c, "failed to update member")
	}

	return httputil.Success(c, map[string]string{"message": "member updated"})
}

// RemoveMember removes a member from project
func (h *ProjectHandler) RemoveMember(c *fiber.Ctx) error {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		return httputil.Unauthorized(c, "")
	}

	projectID, err := uuid.Parse(c.Params("id"))
	if err != nil {
		return httputil.BadRequest(c, "invalid project ID")
	}

	memberID, err := uuid.Parse(c.Params("member_id"))
	if err != nil {
		return httputil.BadRequest(c, "invalid member ID")
	}

	if !h.canManage(c.Context(), projectID, userID) {
		return httputil.Forbidden(c, "insufficient permissions")
	}

	// Check if trying to remove owner
	var memberRole commonModels.MemberRole
	err = h.db.QueryRow(c.Context(),
		"SELECT role FROM project_members WHERE id = $1 AND project_id = $2",
		memberID, projectID,
	).Scan(&memberRole)
	if err != nil {
		return httputil.NotFound(c, "member")
	}
	if memberRole == commonModels.MemberRoleOwner {
		return httputil.BadRequest(c, "cannot remove project owner")
	}

	_, err = h.db.Exec(c.Context(),
		"UPDATE project_members SET left_at = $1 WHERE id = $2 AND project_id = $3",
		time.Now(), memberID, projectID,
	)
	if err != nil {
		return httputil.InternalError(c, "failed to remove member")
	}

	return httputil.NoContent(c)
}

// Helper methods

func (h *ProjectHandler) isMember(ctx interface{}, projectID, userID uuid.UUID) bool {
	var exists bool
	_ = h.db.QueryRow(ctx.(interface {
		Done() <-chan struct{}
	}).(interface {
		Deadline() (time.Time, bool)
		Err() error
		Value(key interface{}) interface{}
	}).(interface {
		Done() <-chan struct{}
		Deadline() (time.Time, bool)
	}).(interface {
		Err() error
	}).(interface {
		Value(key interface{}) interface{}
		Done() <-chan struct{}
		Deadline() (time.Time, bool)
		Err() error
	}),
		"SELECT EXISTS(SELECT 1 FROM project_members WHERE project_id = $1 AND user_id = $2 AND left_at IS NULL)",
		projectID, userID,
	).Scan(&exists)
	return exists
}

func (h *ProjectHandler) canManage(ctx interface{}, projectID, userID uuid.UUID) bool {
	var role commonModels.MemberRole
	err := h.db.QueryRow(ctx.(interface {
		Done() <-chan struct{}
		Deadline() (time.Time, bool)
		Err() error
		Value(key interface{}) interface{}
	}),
		"SELECT role FROM project_members WHERE project_id = $1 AND user_id = $2 AND left_at IS NULL",
		projectID, userID,
	).Scan(&role)
	if err != nil {
		return false
	}
	return role == commonModels.MemberRoleOwner || role == commonModels.MemberRoleAdmin
}

func toProjectResponse(p *models.Project, memberCount int, progress models.ProjectProgress) ProjectResponse {
	resp := ProjectResponse{
		ID:          p.ID.String(),
		Name:        p.Name,
		Description: p.Description,
		Status:      string(p.Status),
		Methodology: string(p.Methodology),
		Color:       p.Color,
		Icon:        p.Icon,
		OwnerID:     p.OwnerID.String(),
		Progress:    progress,
		MemberCount: memberCount,
		CreatedAt:   p.CreatedAt.Format(time.RFC3339),
		UpdatedAt:   p.UpdatedAt.Format(time.RFC3339),
	}

	if p.StartDate != nil {
		s := p.StartDate.Format(time.RFC3339)
		resp.StartDate = &s
	}
	if p.TargetDate != nil {
		t := p.TargetDate.Format(time.RFC3339)
		resp.TargetDate = &t
	}

	return resp
}
