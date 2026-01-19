// Package ai provides AI services for task processing across all domains.
package ai

import (
	"context"
	"encoding/json"
	"fmt"
	"regexp"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/csaptu/flow/pkg/llm"
	"github.com/csaptu/flow/shared/repository"
)

// UserTier represents subscription level
type UserTier string

const (
	TierFree    UserTier = "free"
	TierLight   UserTier = "light"
	TierPremium UserTier = "premium"
)

// AIFeature represents an AI feature type
type AIFeature string

const (
	FeatureCleanTitle         AIFeature = "clean_title"
	FeatureCleanDescription   AIFeature = "clean_description"
	FeatureSmartDueDate       AIFeature = "smart_due_date"
	FeatureReminder           AIFeature = "reminder"
	FeatureDecompose          AIFeature = "decompose"
	FeatureComplexity         AIFeature = "complexity"
	FeatureEntityExtraction   AIFeature = "entity_extraction"
	FeatureRecurringDetection AIFeature = "recurring_detection"
	FeatureAutoGroup          AIFeature = "auto_group"
	FeatureDraftEmail         AIFeature = "draft_email"
	FeatureDraftCalendar      AIFeature = "draft_calendar"
)

// FeatureLimits defines daily limits by tier
var FeatureLimits = map[UserTier]map[AIFeature]int{
	TierFree: {
		FeatureCleanTitle:       20,
		FeatureCleanDescription: 20,
		FeatureSmartDueDate:     -1,
		FeatureReminder:         -1,
	},
	TierLight: {
		FeatureCleanTitle:         -1,
		FeatureCleanDescription:   -1,
		FeatureSmartDueDate:       -1,
		FeatureReminder:           -1,
		FeatureDecompose:          30,
		FeatureComplexity:         -1,
		FeatureEntityExtraction:   -1,
		FeatureRecurringDetection: -1,
		FeatureAutoGroup:          10,
		FeatureDraftEmail:         10,
		FeatureDraftCalendar:      10,
	},
	TierPremium: {
		FeatureCleanTitle:         -1,
		FeatureCleanDescription:   -1,
		FeatureSmartDueDate:       -1,
		FeatureReminder:           -1,
		FeatureDecompose:          -1,
		FeatureComplexity:         -1,
		FeatureEntityExtraction:   -1,
		FeatureRecurringDetection: -1,
		FeatureAutoGroup:          -1,
		FeatureDraftEmail:         -1,
		FeatureDraftCalendar:      -1,
	},
}

// Entity represents an extracted entity
type Entity struct {
	Type  string `json:"type"`
	Value string `json:"value"`
	Start int    `json:"start"`
	End   int    `json:"end"`
}

// DraftContent represents an email or calendar draft
type DraftContent struct {
	Type      string   `json:"type"`
	To        string   `json:"to,omitempty"`
	Subject   string   `json:"subject,omitempty"`
	Body      string   `json:"body,omitempty"`
	Title     string   `json:"title,omitempty"`
	StartTime string   `json:"start_time,omitempty"`
	EndTime   string   `json:"end_time,omitempty"`
	Attendees []string `json:"attendees,omitempty"`
}

// AIProcessResult contains all AI processing results
type AIProcessResult struct {
	CleanedTitle   *string       `json:"cleaned_title,omitempty"`
	CleanedDesc    *string       `json:"cleaned_description,omitempty"`
	Summary        *string       `json:"summary,omitempty"`
	DueDate        *time.Time    `json:"due_date,omitempty"`
	ReminderTime   *time.Time    `json:"reminder_time,omitempty"`
	Complexity     *int          `json:"complexity,omitempty"`
	Entities       []Entity      `json:"entities,omitempty"`
	RecurrenceRule *string       `json:"recurrence_rule,omitempty"`
	SuggestedGroup *string       `json:"suggested_group,omitempty"`
	Draft          *DraftContent `json:"draft,omitempty"`
}

// Service handles all AI operations
type Service struct {
	llm     *llm.MultiClient
	configs map[string]string
}

// NewService creates a new AI service
func NewService(llmClient *llm.MultiClient) *Service {
	s := &Service{llm: llmClient, configs: make(map[string]string)}
	s.loadPromptConfigs()
	return s
}

// loadPromptConfigs loads AI prompt configurations
func (s *Service) loadPromptConfigs() {
	configs, err := repository.GetAIPromptConfigsAsMap(context.Background())
	if err != nil {
		s.configs = map[string]string{
			"clean_title_instruction":     "Concise, action-oriented title (max 10 words)",
			"summary_instruction":         "Brief summary if description is long (max 20 words)",
			"complexity_instruction":      "1-10 scale (1=trivial like 'buy milk', 10=complex multi-step project)",
			"due_date_instruction":        "ISO 8601 date if mentioned",
			"reminder_instruction":        "ISO 8601 datetime if 'remind me' or similar phrase found",
			"entities_instruction":        "person|place|organization",
			"recurrence_instruction":      "RRULE string if recurring pattern detected",
			"suggested_group_instruction": "Category suggestion based on content",
			"decompose_step_count":        "2-5",
			"decompose_rules":             "Each step should be a single, concrete action\nSteps should be in logical order\nUse action verbs\nKeep each step under 10 words",
		}
		return
	}
	s.configs = configs
}

// ReloadConfigs reloads AI prompt configurations
func (s *Service) ReloadConfigs() {
	s.loadPromptConfigs()
}

func (s *Service) getConfig(key, defaultValue string) string {
	if val, ok := s.configs[key]; ok && val != "" {
		return val
	}
	return defaultValue
}

func (s *Service) getConfigEscaped(key, defaultValue string) string {
	val := s.getConfig(key, defaultValue)
	val = strings.ReplaceAll(val, `\`, `\\`)
	val = strings.ReplaceAll(val, `"`, `\"`)
	return val
}

// GetUserTier retrieves the user's subscription tier
func (s *Service) GetUserTier(ctx context.Context, userID uuid.UUID) (UserTier, error) {
	tier, err := repository.GetUserTier(ctx, userID)
	if err != nil {
		return TierFree, nil
	}
	return UserTier(tier), nil
}

// CheckAndIncrementUsage checks if user can use a feature and increments counter
func (s *Service) CheckAndIncrementUsage(ctx context.Context, userID uuid.UUID, feature AIFeature) (bool, error) {
	tier, err := s.GetUserTier(ctx, userID)
	if err != nil {
		return false, err
	}

	limits, ok := FeatureLimits[tier]
	if !ok {
		return false, fmt.Errorf("unknown tier: %s", tier)
	}

	limit, ok := limits[feature]
	if !ok {
		return false, nil
	}

	if limit == -1 {
		_ = repository.IncrementAIUsage(ctx, userID, string(feature))
		return true, nil
	}

	usage, err := repository.GetAIUsage(ctx, userID)
	if err != nil {
		usage = make(map[string]int)
	}

	currentCount := usage[string(feature)]
	if currentCount >= limit {
		return false, nil
	}

	_ = repository.IncrementAIUsage(ctx, userID, string(feature))
	return true, nil
}

// GetUsageStats returns current usage stats for a user
func (s *Service) GetUsageStats(ctx context.Context, userID uuid.UUID) (map[string]interface{}, error) {
	tier, _ := s.GetUserTier(ctx, userID)
	usage, err := repository.GetAIUsage(ctx, userID)
	if err != nil {
		usage = make(map[string]int)
	}

	return map[string]interface{}{
		"tier":   tier,
		"usage":  usage,
		"limits": FeatureLimits[tier],
	}, nil
}

// SaveDraft stores an AI-generated draft
func (s *Service) SaveDraft(ctx context.Context, userID, taskID uuid.UUID, draft *DraftContent) (uuid.UUID, error) {
	contentJSON, _ := json.Marshal(draft)
	return repository.SaveAIDraft(ctx, userID, taskID, draft.Type, contentJSON)
}

// GetPendingDrafts retrieves pending drafts for a user
func (s *Service) GetPendingDrafts(ctx context.Context, userID uuid.UUID) ([]map[string]interface{}, error) {
	drafts, err := repository.GetPendingAIDrafts(ctx, userID)
	if err != nil {
		return nil, err
	}

	// Parse content JSON for each draft
	for i, draft := range drafts {
		if content, ok := draft["content"].([]byte); ok {
			var contentMap map[string]interface{}
			if json.Unmarshal(content, &contentMap) == nil {
				drafts[i]["content"] = contentMap
			}
		}
	}

	return drafts, nil
}

// ProcessTaskOnSave runs auto-triggered AI features on task save
func (s *Service) ProcessTaskOnSave(ctx context.Context, userID uuid.UUID, taskID uuid.UUID, title, description string) (*AIProcessResult, error) {
	if s.llm == nil {
		return nil, fmt.Errorf("AI service not available")
	}

	tier, _ := s.GetUserTier(ctx, userID)
	result := &AIProcessResult{}

	prompt := s.buildAutoProcessPrompt(tier, title, description)

	resp, err := s.llm.Complete(ctx, llm.CompletionRequest{
		Messages: []llm.Message{
			{Role: "user", Content: prompt},
		},
		MaxTokens:   1000,
		Temperature: 0.2,
	})

	if err != nil {
		return nil, fmt.Errorf("AI processing failed: %w", err)
	}

	if err := s.parseAutoProcessResponse(resp.Content, result); err != nil {
		return nil, err
	}

	s.trackAutoProcessUsage(ctx, userID, tier, result)

	return result, nil
}

func (s *Service) buildAutoProcessPrompt(tier UserTier, title, description string) string {
	today := time.Now().Format("2006-01-02")
	dayOfWeek := time.Now().Weekday().String()

	cleanTitleInstr := s.getConfigEscaped("clean_title_instruction", "Concise, action-oriented title (max 10 words)")
	summaryInstr := s.getConfigEscaped("summary_instruction", "Brief summary if description is long (max 20 words)")
	dueDateInstr := s.getConfigEscaped("due_date_instruction", "ISO 8601 date if mentioned")
	reminderInstr := s.getConfigEscaped("reminder_instruction", "ISO 8601 datetime if 'remind me' or similar phrase found")
	complexityInstr := s.getConfigEscaped("complexity_instruction", "1-10 scale (1=trivial, 10=complex)")

	basePrompt := fmt.Sprintf(`Analyze this task and extract information. Today is %s (%s).

Task Title: %s
Description: %s

Return a JSON object with these fields (omit fields if not applicable):

{
  "cleaned_title": "%s",
  "summary": "%s",
  "due_date": "%s",
  "reminder_time": "%s",
  "complexity": %s`, today, dayOfWeek, title, description, cleanTitleInstr, summaryInstr, dueDateInstr, reminderInstr, complexityInstr)

	if tier == TierLight || tier == TierPremium {
		entitiesInstr := s.getConfigEscaped("entities_instruction", "person|place|organization")
		recurrenceInstr := s.getConfigEscaped("recurrence_instruction", "RRULE string if recurring pattern detected")
		suggestedGroupInstr := s.getConfigEscaped("suggested_group_instruction", "Category suggestion based on content")

		basePrompt += fmt.Sprintf(`,
  "entities": [{"type": "%s", "value": "extracted value"}],
  "recurrence_rule": "%s",
  "suggested_group": "%s"`, entitiesInstr, recurrenceInstr, suggestedGroupInstr)
	}

	if (tier == TierLight || tier == TierPremium) && s.containsDraftTrigger(title+" "+description) {
		basePrompt += `,
  "draft": {
    "type": "email or calendar based on context",
    "to": "recipient if mentioned",
    "subject": "email subject",
    "body": "professional email body",
    "title": "calendar event title",
    "start_time": "suggested start time ISO 8601",
    "end_time": "suggested end time ISO 8601",
    "attendees": ["list of attendees"]
  }`
	}

	basePrompt += `
}

IMPORTANT:
- Only include fields that apply to this task
- Dates should be ISO 8601 format
- Be concise and practical
- Return ONLY valid JSON, no markdown or explanation`

	return basePrompt
}

func (s *Service) containsDraftTrigger(text string) bool {
	text = strings.ToLower(text)
	triggers := []string{"email", "tell ", "message ", "contact ", "meet with", "meeting", "schedule ", "call with"}
	for _, trigger := range triggers {
		if strings.Contains(text, trigger) {
			return true
		}
	}
	return false
}

func (s *Service) parseAutoProcessResponse(content string, result *AIProcessResult) error {
	content = strings.TrimSpace(content)
	if strings.HasPrefix(content, "```") {
		re := regexp.MustCompile("```(?:json)?\\s*([\\s\\S]*?)\\s*```")
		matches := re.FindStringSubmatch(content)
		if len(matches) > 1 {
			content = matches[1]
		}
	}

	var parsed struct {
		CleanedTitle   string        `json:"cleaned_title"`
		Summary        string        `json:"summary"`
		DueDate        string        `json:"due_date"`
		ReminderTime   string        `json:"reminder_time"`
		Complexity     int           `json:"complexity"`
		Entities       []Entity      `json:"entities"`
		RecurrenceRule string        `json:"recurrence_rule"`
		SuggestedGroup string        `json:"suggested_group"`
		Draft          *DraftContent `json:"draft"`
	}

	if err := json.Unmarshal([]byte(content), &parsed); err != nil {
		return fmt.Errorf("failed to parse AI response: %w", err)
	}

	if parsed.CleanedTitle != "" {
		result.CleanedTitle = &parsed.CleanedTitle
	}
	if parsed.Summary != "" {
		result.Summary = &parsed.Summary
	}
	if parsed.DueDate != "" {
		if t, err := time.Parse(time.RFC3339, parsed.DueDate); err == nil {
			result.DueDate = &t
		} else if t, err := time.Parse("2006-01-02", parsed.DueDate); err == nil {
			result.DueDate = &t
		}
	}
	if parsed.ReminderTime != "" {
		if t, err := time.Parse(time.RFC3339, parsed.ReminderTime); err == nil {
			result.ReminderTime = &t
		}
	}
	if parsed.Complexity > 0 {
		result.Complexity = &parsed.Complexity
	}
	if len(parsed.Entities) > 0 {
		result.Entities = parsed.Entities
	}
	if parsed.RecurrenceRule != "" {
		result.RecurrenceRule = &parsed.RecurrenceRule
	}
	if parsed.SuggestedGroup != "" {
		result.SuggestedGroup = &parsed.SuggestedGroup
	}
	if parsed.Draft != nil {
		result.Draft = parsed.Draft
	}

	return nil
}

func (s *Service) trackAutoProcessUsage(ctx context.Context, userID uuid.UUID, tier UserTier, result *AIProcessResult) {
	if result.CleanedTitle != nil {
		_ = repository.IncrementAIUsage(ctx, userID, string(FeatureCleanTitle))
	}
	if result.Summary != nil {
		_ = repository.IncrementAIUsage(ctx, userID, string(FeatureCleanDescription))
	}
	if result.DueDate != nil {
		_ = repository.IncrementAIUsage(ctx, userID, string(FeatureSmartDueDate))
	}
	if result.ReminderTime != nil {
		_ = repository.IncrementAIUsage(ctx, userID, string(FeatureReminder))
	}
	if tier != TierFree {
		if result.Complexity != nil {
			_ = repository.IncrementAIUsage(ctx, userID, string(FeatureComplexity))
		}
		if len(result.Entities) > 0 {
			_ = repository.IncrementAIUsage(ctx, userID, string(FeatureEntityExtraction))
		}
		if result.RecurrenceRule != nil {
			_ = repository.IncrementAIUsage(ctx, userID, string(FeatureRecurringDetection))
		}
		if result.SuggestedGroup != nil {
			_ = repository.IncrementAIUsage(ctx, userID, string(FeatureAutoGroup))
		}
		if result.Draft != nil {
			if result.Draft.Type == "email" {
				_ = repository.IncrementAIUsage(ctx, userID, string(FeatureDraftEmail))
			} else {
				_ = repository.IncrementAIUsage(ctx, userID, string(FeatureDraftCalendar))
			}
		}
	}
}

// IsAvailable returns whether the AI service is available
func (s *Service) IsAvailable() bool {
	return s.llm != nil
}

// LLM returns the underlying LLM client
func (s *Service) LLM() *llm.MultiClient {
	return s.llm
}
