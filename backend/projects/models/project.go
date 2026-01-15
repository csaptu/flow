package models

import (
	"time"

	"github.com/google/uuid"
	"github.com/tupham/flow/common/models"
)

// Project represents a project in the projects domain
type Project struct {
	ID          uuid.UUID              `json:"id" db:"id"`
	Name        string                 `json:"name" db:"name"`
	Description *string                `json:"description,omitempty" db:"description"`
	Status      models.ProjectStatus   `json:"status" db:"status"`
	Methodology models.Methodology     `json:"methodology" db:"methodology"`
	Color       *string                `json:"color,omitempty" db:"color"`
	Icon        *string                `json:"icon,omitempty" db:"icon"`
	StartDate   *time.Time             `json:"start_date,omitempty" db:"start_date"`
	TargetDate  *time.Time             `json:"target_date,omitempty" db:"target_date"`
	OwnerID     uuid.UUID              `json:"owner_id" db:"owner_id"`
	CreatedAt   time.Time              `json:"created_at" db:"created_at"`
	UpdatedAt   time.Time              `json:"updated_at" db:"updated_at"`
	DeletedAt   *time.Time             `json:"deleted_at,omitempty" db:"deleted_at"`
}

// ProjectMember represents a team member in a project
type ProjectMember struct {
	ID        uuid.UUID        `json:"id" db:"id"`
	ProjectID uuid.UUID        `json:"project_id" db:"project_id"`
	UserID    uuid.UUID        `json:"user_id" db:"user_id"`
	Role      models.MemberRole `json:"role" db:"role"`
	JoinedAt  time.Time        `json:"joined_at" db:"joined_at"`
	LeftAt    *time.Time       `json:"left_at,omitempty" db:"left_at"`
}

// NewProject creates a new project with default values
func NewProject(name string, ownerID uuid.UUID) *Project {
	now := time.Now()
	return &Project{
		ID:          uuid.New(),
		Name:        name,
		Status:      models.ProjectStatusPlanning,
		Methodology: models.MethodologyWaterfall,
		OwnerID:     ownerID,
		CreatedAt:   now,
		UpdatedAt:   now,
	}
}

// IsOwner checks if a user is the project owner
func (p *Project) IsOwner(userID uuid.UUID) bool {
	return p.OwnerID == userID
}

// Progress calculates project completion percentage based on WBS nodes
type ProjectProgress struct {
	TotalNodes     int     `json:"total_nodes"`
	CompletedNodes int     `json:"completed_nodes"`
	Percentage     float64 `json:"percentage"`
}

// CalculateProgress calculates progress from completed vs total nodes
func (p *Project) CalculateProgress(total, completed int) ProjectProgress {
	var percentage float64
	if total > 0 {
		percentage = float64(completed) / float64(total) * 100
	}
	return ProjectProgress{
		TotalNodes:     total,
		CompletedNodes: completed,
		Percentage:     percentage,
	}
}
