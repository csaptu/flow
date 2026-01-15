package models

// Status represents the status of a task or WBS node
type Status string

const (
	StatusPending    Status = "pending"
	StatusInProgress Status = "in_progress"
	StatusCompleted  Status = "completed"
	StatusCancelled  Status = "cancelled"
	StatusArchived   Status = "archived"
)

// IsValid checks if the status is valid
func (s Status) IsValid() bool {
	switch s {
	case StatusPending, StatusInProgress, StatusCompleted, StatusCancelled, StatusArchived:
		return true
	}
	return false
}

// Priority represents the priority level of a task
type Priority int

const (
	PriorityNone   Priority = 0
	PriorityLow    Priority = 1
	PriorityMedium Priority = 2
	PriorityHigh   Priority = 3
	PriorityUrgent Priority = 4
)

// IsValid checks if the priority is valid
func (p Priority) IsValid() bool {
	return p >= PriorityNone && p <= PriorityUrgent
}

// DependencyType represents the type of task dependency
type DependencyType string

const (
	DependencyFS DependencyType = "FS" // Finish-to-Start (most common)
	DependencySS DependencyType = "SS" // Start-to-Start
	DependencyFF DependencyType = "FF" // Finish-to-Finish
	DependencySF DependencyType = "SF" // Start-to-Finish
)

// IsValid checks if the dependency type is valid
func (d DependencyType) IsValid() bool {
	switch d {
	case DependencyFS, DependencySS, DependencyFF, DependencySF:
		return true
	}
	return false
}

// ProjectStatus represents the status of a project
type ProjectStatus string

const (
	ProjectStatusPlanning  ProjectStatus = "planning"
	ProjectStatusActive    ProjectStatus = "active"
	ProjectStatusOnHold    ProjectStatus = "on_hold"
	ProjectStatusCompleted ProjectStatus = "completed"
	ProjectStatusCancelled ProjectStatus = "cancelled"
)

// IsValid checks if the project status is valid
func (s ProjectStatus) IsValid() bool {
	switch s {
	case ProjectStatusPlanning, ProjectStatusActive, ProjectStatusOnHold, ProjectStatusCompleted, ProjectStatusCancelled:
		return true
	}
	return false
}

// Methodology represents the project management methodology
type Methodology string

const (
	MethodologyWaterfall Methodology = "waterfall"
	MethodologyAgile     Methodology = "agile"
	MethodologyHybrid    Methodology = "hybrid"
	MethodologyKanban    Methodology = "kanban"
)

// IsValid checks if the methodology is valid
func (m Methodology) IsValid() bool {
	switch m {
	case MethodologyWaterfall, MethodologyAgile, MethodologyHybrid, MethodologyKanban:
		return true
	}
	return false
}

// MemberRole represents a team member's role in a project
type MemberRole string

const (
	MemberRoleOwner  MemberRole = "owner"
	MemberRoleAdmin  MemberRole = "admin"
	MemberRoleMember MemberRole = "member"
	MemberRoleViewer MemberRole = "viewer"
)

// IsValid checks if the member role is valid
func (r MemberRole) IsValid() bool {
	switch r {
	case MemberRoleOwner, MemberRoleAdmin, MemberRoleMember, MemberRoleViewer:
		return true
	}
	return false
}

// SubscriptionTier represents the user's subscription tier
type SubscriptionTier string

const (
	TierFree    SubscriptionTier = "free"
	TierLight   SubscriptionTier = "light"
	TierPremium SubscriptionTier = "premium"
)

// IsValid checks if the subscription tier is valid
func (t SubscriptionTier) IsValid() bool {
	switch t {
	case TierFree, TierLight, TierPremium:
		return true
	}
	return false
}
