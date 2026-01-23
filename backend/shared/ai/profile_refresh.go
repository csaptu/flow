package ai

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/csaptu/flow/pkg/llm"
	"github.com/csaptu/flow/shared/repository"
)

// ProfileRefreshTrigger defines what triggered a profile refresh
type ProfileRefreshTrigger string

const (
	TriggerManual       ProfileRefreshTrigger = "manual"
	TriggerScheduled    ProfileRefreshTrigger = "scheduled"
	TriggerTaskMilestone ProfileRefreshTrigger = "task_milestone"
)

// ProfileRefreshConfig holds configuration for profile refresh
type ProfileRefreshConfig struct {
	TaskDaysToAnalyze    int // How many days of tasks to analyze
	MaxTasksToAnalyze    int // Maximum number of tasks to analyze
	TaskMilestoneCount   int // Number of tasks that triggers auto-refresh
	ScheduledRefreshHours int // Hours between scheduled refreshes
}

// DefaultProfileRefreshConfig returns the default refresh configuration
func DefaultProfileRefreshConfig() ProfileRefreshConfig {
	return ProfileRefreshConfig{
		TaskDaysToAnalyze:    30,
		MaxTasksToAnalyze:    100,
		TaskMilestoneCount:   10,
		ScheduledRefreshHours: 24,
	}
}

// ProfileRefresher handles AI profile generation and refresh
type ProfileRefresher struct {
	llm           *llm.MultiClient
	config        ProfileRefreshConfig
	postProcessor *PostProcessor
}

// NewProfileRefresher creates a new profile refresher
func NewProfileRefresher(llmClient *llm.MultiClient) *ProfileRefresher {
	return &ProfileRefresher{
		llm:           llmClient,
		config:        DefaultProfileRefreshConfig(),
		postProcessor: NewPostProcessor(),
	}
}

// SetConfig sets custom refresh configuration
func (pr *ProfileRefresher) SetConfig(config ProfileRefreshConfig) {
	pr.config = config
}

// ProfileAnalysisResult contains the AI-generated profile fields
type ProfileAnalysisResult struct {
	IdentitySummary       string `json:"identity_summary"`
	CommunicationStyle    string `json:"communication_style"`
	WorkContext           string `json:"work_context"`
	PersonalContext       string `json:"personal_context"`
	SocialGraph           string `json:"social_graph"`
	LocationsContext      string `json:"locations_context"`
	RoutinePatterns       string `json:"routine_patterns"`
	TaskStylePreferences  string `json:"task_style_preferences"`
	GoalsAndPriorities    string `json:"goals_and_priorities"`
	RecentActivitySummary string `json:"recent_activity_summary"`
	CurrentFocus          string `json:"current_focus"`
	UpcomingCommitments   string `json:"upcoming_commitments"`
}

// RefreshUserProfile generates or refreshes a user's AI profile
func (pr *ProfileRefresher) RefreshUserProfile(ctx context.Context, userID uuid.UUID, trigger ProfileRefreshTrigger) error {
	if pr.llm == nil {
		return fmt.Errorf("LLM client not available")
	}

	// Fetch recent tasks
	tasks, err := repository.GetRecentTasksForProfile(ctx, userID, pr.config.TaskDaysToAnalyze, pr.config.MaxTasksToAnalyze)
	if err != nil {
		return fmt.Errorf("failed to fetch tasks: %w", err)
	}

	if len(tasks) == 0 {
		// Create an empty profile if no tasks exist
		return repository.CreateEmptyProfile(ctx, userID)
	}

	// Get existing profile (for context, if any)
	existingProfile, _ := repository.GetUserAIProfile(ctx, userID)

	// Build analysis prompt
	prompt := pr.buildAnalysisPrompt(tasks, existingProfile)

	// Call LLM
	resp, err := pr.llm.Complete(ctx, llm.CompletionRequest{
		Messages: []llm.Message{
			{Role: "user", Content: prompt},
		},
		MaxTokens:   2000,
		Temperature: 0.3,
	})
	if err != nil {
		return fmt.Errorf("LLM completion failed: %w", err)
	}

	// Parse response
	result, err := pr.parseAnalysisResponse(resp.Content)
	if err != nil {
		return fmt.Errorf("failed to parse response: %w", err)
	}

	// Save to database
	profile := pr.resultToProfile(userID, result, trigger)
	if err := repository.UpsertUserAIProfile(ctx, profile); err != nil {
		return fmt.Errorf("failed to save profile: %w", err)
	}

	return nil
}

// buildAnalysisPrompt creates the prompt for profile analysis
func (pr *ProfileRefresher) buildAnalysisPrompt(tasks []repository.TaskSummary, existingProfile *repository.UserAIProfile) string {
	var sb strings.Builder

	sb.WriteString("Analyze these tasks to build a user profile for personalized assistance.\n\n")
	sb.WriteString("TASKS (most recent first):\n")

	for i, t := range tasks {
		if i >= 50 { // Limit to 50 for prompt size
			sb.WriteString(fmt.Sprintf("... and %d more tasks\n", len(tasks)-50))
			break
		}

		status := t.Status
		if t.CompletedAt != nil {
			status = "completed"
		}

		line := fmt.Sprintf("- [%s] %s", status, t.Title)
		if t.Description != nil && *t.Description != "" {
			desc := *t.Description
			if len(desc) > 100 {
				desc = desc[:100] + "..."
			}
			line += fmt.Sprintf(" | %s", desc)
		}
		if len(t.Tags) > 0 {
			line += fmt.Sprintf(" #%s", strings.Join(t.Tags, " #"))
		}
		if t.DueAt != nil {
			line += fmt.Sprintf(" (due: %s)", *t.DueAt)
		}
		sb.WriteString(line + "\n")
	}

	// Include existing profile as context (if available)
	if existingProfile != nil && existingProfile.IdentitySummary != nil && *existingProfile.IdentitySummary != "" {
		sb.WriteString("\nEXISTING PROFILE (update if new info available):\n")
		if existingProfile.IdentitySummary != nil {
			sb.WriteString(fmt.Sprintf("- Identity: %s\n", *existingProfile.IdentitySummary))
		}
		if existingProfile.WorkContext != nil {
			sb.WriteString(fmt.Sprintf("- Work: %s\n", *existingProfile.WorkContext))
		}
	}

	sb.WriteString(`
Generate a JSON profile with these fields (keep each under 200 chars, be specific):

{
  "identity_summary": "Who this person is - role, background",
  "communication_style": "How they communicate - tone, verbosity, formality",
  "work_context": "Their job, projects, responsibilities",
  "personal_context": "Family, hobbies, personal interests",
  "social_graph": "Key people mentioned (names, relationships)",
  "locations_context": "Frequent places mentioned",
  "routine_patterns": "Daily/weekly patterns observed",
  "task_style_preferences": "How they structure and describe tasks",
  "goals_and_priorities": "Stated or implied goals",
  "recent_activity_summary": "Summary of last 7 days activity",
  "current_focus": "What they seem focused on currently",
  "upcoming_commitments": "Upcoming deadlines or events"
}

RULES:
- Use "Unknown" if not enough data for a field
- Be concise but specific
- Include real names/places when mentioned
- Return ONLY valid JSON, no markdown`)

	return sb.String()
}

// parseAnalysisResponse parses the LLM response into a ProfileAnalysisResult
func (pr *ProfileRefresher) parseAnalysisResponse(content string) (*ProfileAnalysisResult, error) {
	// Use post-processor to extract JSON
	_, jsonContent, err := pr.postProcessor.ProcessAndExtractJSON(content)
	if err != nil {
		// Try to parse as-is
		jsonContent = content
	}

	var result ProfileAnalysisResult
	if err := json.Unmarshal([]byte(jsonContent), &result); err != nil {
		return nil, err
	}

	return &result, nil
}

// resultToProfile converts analysis result to a UserAIProfile
func (pr *ProfileRefresher) resultToProfile(userID uuid.UUID, result *ProfileAnalysisResult, trigger ProfileRefreshTrigger) *repository.UserAIProfile {
	profile := &repository.UserAIProfile{
		UserID:            userID,
		LastRefreshedAt:   time.Now(),
		TasksSinceRefresh: 0,
	}

	triggerStr := string(trigger)
	profile.RefreshTrigger = &triggerStr

	// Set fields, converting empty strings and "Unknown" to nil
	setField := func(value string) *string {
		value = strings.TrimSpace(value)
		if value == "" || strings.ToLower(value) == "unknown" {
			return nil
		}
		return &value
	}

	profile.IdentitySummary = setField(result.IdentitySummary)
	profile.CommunicationStyle = setField(result.CommunicationStyle)
	profile.WorkContext = setField(result.WorkContext)
	profile.PersonalContext = setField(result.PersonalContext)
	profile.SocialGraph = setField(result.SocialGraph)
	profile.LocationsContext = setField(result.LocationsContext)
	profile.RoutinePatterns = setField(result.RoutinePatterns)
	profile.TaskStylePreferences = setField(result.TaskStylePreferences)
	profile.GoalsAndPriorities = setField(result.GoalsAndPriorities)
	profile.RecentActivitySummary = setField(result.RecentActivitySummary)
	profile.CurrentFocus = setField(result.CurrentFocus)
	profile.UpcomingCommitments = setField(result.UpcomingCommitments)

	return profile
}

// ShouldRefresh checks if a user's profile should be refreshed
func (pr *ProfileRefresher) ShouldRefresh(ctx context.Context, userID uuid.UUID) (bool, ProfileRefreshTrigger) {
	profile, err := repository.GetUserAIProfile(ctx, userID)
	if err != nil || profile == nil {
		return true, TriggerManual // New user, needs initial profile
	}

	// Check task milestone
	if profile.TasksSinceRefresh >= pr.config.TaskMilestoneCount {
		return true, TriggerTaskMilestone
	}

	// Check scheduled refresh
	hoursSinceRefresh := time.Since(profile.LastRefreshedAt).Hours()
	if hoursSinceRefresh >= float64(pr.config.ScheduledRefreshHours) {
		return true, TriggerScheduled
	}

	return false, ""
}

// RefreshIfNeeded checks if refresh is needed and triggers it
func (pr *ProfileRefresher) RefreshIfNeeded(ctx context.Context, userID uuid.UUID) error {
	shouldRefresh, trigger := pr.ShouldRefresh(ctx, userID)
	if !shouldRefresh {
		return nil
	}

	return pr.RefreshUserProfile(ctx, userID, trigger)
}

// GetUsersNeedingRefresh returns users whose profiles need refreshing
func (pr *ProfileRefresher) GetUsersNeedingRefresh(ctx context.Context) ([]repository.UserNeedingRefresh, error) {
	return repository.GetUsersNeedingProfileRefresh(
		ctx,
		pr.config.TaskMilestoneCount,
		pr.config.ScheduledRefreshHours,
	)
}

// BatchRefreshProfiles refreshes profiles for multiple users
func (pr *ProfileRefresher) BatchRefreshProfiles(ctx context.Context, userIDs []uuid.UUID) (int, []error) {
	var errors []error
	successCount := 0

	for _, userID := range userIDs {
		if err := pr.RefreshUserProfile(ctx, userID, TriggerScheduled); err != nil {
			errors = append(errors, fmt.Errorf("user %s: %w", userID, err))
		} else {
			successCount++
		}
	}

	return successCount, errors
}
