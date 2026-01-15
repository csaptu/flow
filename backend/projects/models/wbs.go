package models

import (
	"time"

	"github.com/google/uuid"
	"github.com/csaptu/flow/common/models"
)

// WBSNode represents a Work Breakdown Structure node
// Unlike Tasks (2-layer limit), WBS supports unlimited depth
type WBSNode struct {
	models.TaskBase

	// Project hierarchy
	ProjectID uuid.UUID  `json:"project_id" db:"project_id"`
	ParentID  *uuid.UUID `json:"parent_id,omitempty" db:"parent_id"`
	Depth     int        `json:"depth" db:"depth"`
	Path      string     `json:"path" db:"path"` // Materialized path for fast queries (e.g., "1.2.3")
	Position  int        `json:"position" db:"position"` // Order within parent

	// Assignment
	AssigneeID *uuid.UUID `json:"assignee_id,omitempty" db:"assignee_id"`

	// Scheduling (for Gantt)
	PlannedStart    *time.Time `json:"planned_start,omitempty" db:"planned_start"`
	PlannedEnd      *time.Time `json:"planned_end,omitempty" db:"planned_end"`
	ActualStart     *time.Time `json:"actual_start,omitempty" db:"actual_start"`
	ActualEnd       *time.Time `json:"actual_end,omitempty" db:"actual_end"`
	Duration        *int       `json:"duration,omitempty" db:"duration"` // In days
	Progress        float64    `json:"progress" db:"progress"`           // 0-100

	// Agile fields (optional)
	StoryPoints *int    `json:"story_points,omitempty" db:"story_points"`
	SprintID    *uuid.UUID `json:"sprint_id,omitempty" db:"sprint_id"`

	// Promoted from Tasks
	PromotedFromTask *uuid.UUID `json:"promoted_from_task,omitempty" db:"promoted_from_task"`

	// Critical path flag (calculated)
	IsCritical bool `json:"is_critical" db:"is_critical"`

	// Version for optimistic locking
	Version int `json:"version" db:"version"`
}

// WBSDependency represents a dependency between WBS nodes
type WBSDependency struct {
	ID             uuid.UUID              `json:"id" db:"id"`
	ProjectID      uuid.UUID              `json:"project_id" db:"project_id"`
	PredecessorID  uuid.UUID              `json:"predecessor_id" db:"predecessor_id"`
	SuccessorID    uuid.UUID              `json:"successor_id" db:"successor_id"`
	DependencyType models.DependencyType  `json:"dependency_type" db:"dependency_type"`
	LagDays        int                    `json:"lag_days" db:"lag_days"` // Can be negative for lead time
	CreatedAt      time.Time              `json:"created_at" db:"created_at"`
}

// NewWBSNode creates a new WBS node
func NewWBSNode(projectID, userID uuid.UUID, title string) *WBSNode {
	now := time.Now()
	return &WBSNode{
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
		ProjectID: projectID,
		Depth:     0,
		Path:      "",
		Position:  0,
		Progress:  0,
		Version:   1,
	}
}

// SetParent sets the parent node and updates depth/path
func (n *WBSNode) SetParent(parentID uuid.UUID, parentPath string, parentDepth int) {
	n.ParentID = &parentID
	n.Depth = parentDepth + 1
	// Path will be set by the repository layer with proper position
}

// UpdateProgress updates the progress based on child nodes or manual input
func (n *WBSNode) UpdateProgress(progress float64) {
	if progress < 0 {
		progress = 0
	}
	if progress > 100 {
		progress = 100
	}
	n.Progress = progress
	n.UpdatedAt = time.Now()

	// Auto-complete if 100%
	if progress == 100 && n.Status != models.StatusCompleted {
		n.Status = models.StatusCompleted
		now := time.Now()
		n.CompletedAt = &now
	}
}

// CalculateDuration calculates duration from planned dates
func (n *WBSNode) CalculateDuration() int {
	if n.PlannedStart == nil || n.PlannedEnd == nil {
		return 0
	}
	duration := int(n.PlannedEnd.Sub(*n.PlannedStart).Hours() / 24)
	if duration < 0 {
		return 0
	}
	return duration
}

// IsLeaf returns true if this node has no children (checked at query time)
func (n *WBSNode) IsLeaf() bool {
	// This is determined at query time by checking children count
	return false // Placeholder
}

// GanttBar represents a node as a Gantt chart bar
type GanttBar struct {
	ID          string     `json:"id"`
	Title       string     `json:"title"`
	Start       *time.Time `json:"start"`
	End         *time.Time `json:"end"`
	Progress    float64    `json:"progress"`
	AssigneeID  *string    `json:"assignee_id,omitempty"`
	IsCritical  bool       `json:"is_critical"`
	IsMilestone bool       `json:"is_milestone"`
	ParentID    *string    `json:"parent_id,omitempty"`
	Dependencies []string  `json:"dependencies"` // Predecessor IDs
}

// ToGanttBar converts a WBS node to a Gantt bar
func (n *WBSNode) ToGanttBar(dependencies []uuid.UUID) GanttBar {
	bar := GanttBar{
		ID:         n.ID.String(),
		Title:      n.Title,
		Start:      n.PlannedStart,
		End:        n.PlannedEnd,
		Progress:   n.Progress,
		IsCritical: n.IsCritical,
		IsMilestone: n.Duration != nil && *n.Duration == 0,
	}

	if n.AssigneeID != nil {
		a := n.AssigneeID.String()
		bar.AssigneeID = &a
	}
	if n.ParentID != nil {
		p := n.ParentID.String()
		bar.ParentID = &p
	}

	bar.Dependencies = make([]string, len(dependencies))
	for i, dep := range dependencies {
		bar.Dependencies[i] = dep.String()
	}

	return bar
}
