package ai

import (
	"context"
	"fmt"
	"strings"

	"github.com/google/uuid"
	"github.com/csaptu/flow/shared/repository"
)

// AITaskType represents the type of AI task being performed
type AITaskType string

const (
	TaskTypeCleanTitle       AITaskType = "clean_title"
	TaskTypeCleanDescription AITaskType = "clean_description"
	TaskTypeDecompose        AITaskType = "decompose"
	TaskTypeEntityExtraction AITaskType = "entity_extraction"
	TaskTypeRecurring        AITaskType = "recurring"
	TaskTypeDuplicateCheck   AITaskType = "duplicate_check"
	TaskTypeGeneral          AITaskType = "general"
)

// ProfileFieldRelevance defines which profile fields are relevant for each task type
// Only relevant fields are included in context to minimize token usage
var ProfileFieldRelevance = map[AITaskType][]string{
	TaskTypeCleanTitle:       {"communication_style", "task_style_preferences"},
	TaskTypeCleanDescription: {"communication_style", "task_style_preferences"},
	TaskTypeDecompose:        {"task_style_preferences", "work_context", "routine_patterns"},
	TaskTypeEntityExtraction: {"social_graph", "locations_context", "work_context"},
	TaskTypeRecurring:        {"routine_patterns", "work_context"},
	TaskTypeDuplicateCheck:   {"work_context", "task_style_preferences"},
	TaskTypeGeneral: {
		"identity_summary", "communication_style", "work_context",
		"current_focus", "recent_activity_summary",
	},
}

// MaxContextTokens is the target maximum tokens for context (~1000 tokens)
const MaxContextTokens = 1000

// ProfileFieldLabels maps database field names to human-readable labels
var ProfileFieldLabels = map[string]string{
	"identity_summary":        "Identity",
	"communication_style":     "Communication Style",
	"work_context":            "Work Context",
	"personal_context":        "Personal Life",
	"social_graph":            "Key People",
	"locations_context":       "Locations",
	"routine_patterns":        "Routines",
	"task_style_preferences":  "Task Preferences",
	"goals_and_priorities":    "Goals",
	"recent_activity_summary": "Recent Activity",
	"current_focus":           "Current Focus",
	"upcoming_commitments":    "Upcoming",
}

// ContextBuilder assembles AI context based on task type
type ContextBuilder struct {
	firstContext string // System first context from config
}

// NewContextBuilder creates a new context builder
func NewContextBuilder() *ContextBuilder {
	return &ContextBuilder{}
}

// LoadFirstContext loads the system first context from config
func (cb *ContextBuilder) LoadFirstContext(ctx context.Context) error {
	firstCtx, err := repository.GetAIPromptConfig(ctx, "system_first_context")
	if err != nil {
		return err
	}
	if firstCtx != "" {
		cb.firstContext = firstCtx
	}
	return nil
}

// SetFirstContext sets the first context directly (for testing or override)
func (cb *ContextBuilder) SetFirstContext(ctx string) {
	cb.firstContext = ctx
}

// GetFirstContext returns the loaded first context
func (cb *ContextBuilder) GetFirstContext() string {
	return cb.firstContext
}

// BuildContext assembles the full context for an AI request
// Returns: firstContext + userProfileContext
func (cb *ContextBuilder) BuildContext(ctx context.Context, userID uuid.UUID, taskType AITaskType) (string, error) {
	var parts []string

	// 1. Add first context (system prompt)
	if cb.firstContext != "" {
		parts = append(parts, cb.firstContext)
	}

	// 2. Build user profile context
	profileCtx, err := cb.buildUserProfileContext(ctx, userID, taskType)
	if err != nil {
		// Non-fatal: continue without profile
		profileCtx = ""
	}
	if profileCtx != "" {
		parts = append(parts, profileCtx)
	}

	return strings.Join(parts, "\n\n---\n\n"), nil
}

// buildUserProfileContext builds the user-specific context section
func (cb *ContextBuilder) buildUserProfileContext(ctx context.Context, userID uuid.UUID, taskType AITaskType) (string, error) {
	profile, err := repository.GetUserAIProfile(ctx, userID)
	if err != nil {
		return "", err
	}
	if profile == nil {
		return "", nil
	}

	// Get relevant fields for this task type
	relevantFields, ok := ProfileFieldRelevance[taskType]
	if !ok {
		relevantFields = ProfileFieldRelevance[TaskTypeGeneral]
	}

	// Build context from relevant fields
	var contextParts []string
	for _, field := range relevantFields {
		value := cb.getProfileFieldValue(profile, field)
		if value != "" {
			label := ProfileFieldLabels[field]
			if label == "" {
				label = field
			}
			contextParts = append(contextParts, fmt.Sprintf("- %s: %s", label, value))
		}
	}

	if len(contextParts) == 0 {
		return "", nil
	}

	return "USER CONTEXT:\n" + strings.Join(contextParts, "\n"), nil
}

// getProfileFieldValue extracts a field value from the profile struct
func (cb *ContextBuilder) getProfileFieldValue(profile *repository.UserAIProfile, field string) string {
	var value *string
	switch field {
	case "identity_summary":
		value = profile.IdentitySummary
	case "communication_style":
		value = profile.CommunicationStyle
	case "work_context":
		value = profile.WorkContext
	case "personal_context":
		value = profile.PersonalContext
	case "social_graph":
		value = profile.SocialGraph
	case "locations_context":
		value = profile.LocationsContext
	case "routine_patterns":
		value = profile.RoutinePatterns
	case "task_style_preferences":
		value = profile.TaskStylePreferences
	case "goals_and_priorities":
		value = profile.GoalsAndPriorities
	case "recent_activity_summary":
		value = profile.RecentActivitySummary
	case "current_focus":
		value = profile.CurrentFocus
	case "upcoming_commitments":
		value = profile.UpcomingCommitments
	}
	if value == nil {
		return ""
	}
	return *value
}

// BuildContextForFields builds context with specific fields (for testing/custom needs)
func (cb *ContextBuilder) BuildContextForFields(ctx context.Context, userID uuid.UUID, fields []string) (string, error) {
	profile, err := repository.GetUserAIProfile(ctx, userID)
	if err != nil {
		return "", err
	}
	if profile == nil {
		return "", nil
	}

	var contextParts []string
	for _, field := range fields {
		value := cb.getProfileFieldValue(profile, field)
		if value != "" {
			label := ProfileFieldLabels[field]
			if label == "" {
				label = field
			}
			contextParts = append(contextParts, fmt.Sprintf("- %s: %s", label, value))
		}
	}

	if len(contextParts) == 0 {
		return "", nil
	}

	return "USER CONTEXT:\n" + strings.Join(contextParts, "\n"), nil
}

// EstimateTokens provides a rough token estimate (4 chars per token)
func EstimateTokens(text string) int {
	return len(text) / 4
}
