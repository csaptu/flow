package tasks

import (
	"context"
	"encoding/json"
	"fmt"
	"regexp"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
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
	FeatureCleanTitle        AIFeature = "clean_title"
	FeatureCleanDescription  AIFeature = "clean_description"
	FeatureSmartDueDate      AIFeature = "smart_due_date"
	FeatureReminder          AIFeature = "reminder"
	FeatureDecompose         AIFeature = "decompose"
	FeatureComplexity        AIFeature = "complexity"
	FeatureEntityExtraction  AIFeature = "entity_extraction"
	FeatureRecurringDetection AIFeature = "recurring_detection"
	FeatureAutoGroup         AIFeature = "auto_group"
	FeatureDraftEmail        AIFeature = "draft_email"
	FeatureDraftCalendar     AIFeature = "draft_calendar"
)

// Daily limits by tier
var featureLimits = map[UserTier]map[AIFeature]int{
	TierFree: {
		FeatureCleanTitle:       20,
		FeatureCleanDescription: 20,
		FeatureSmartDueDate:     -1, // unlimited
		FeatureReminder:         -1, // unlimited
	},
	TierLight: {
		FeatureCleanTitle:        -1,
		FeatureCleanDescription:  -1,
		FeatureSmartDueDate:      -1,
		FeatureReminder:          -1,
		FeatureDecompose:         30,
		FeatureComplexity:        -1,
		FeatureEntityExtraction:  -1,
		FeatureRecurringDetection: -1,
		FeatureAutoGroup:         10,
		FeatureDraftEmail:        10,
		FeatureDraftCalendar:     10,
	},
	TierPremium: {
		// All unlimited for premium
		FeatureCleanTitle:        -1,
		FeatureCleanDescription:  -1,
		FeatureSmartDueDate:      -1,
		FeatureReminder:          -1,
		FeatureDecompose:         -1,
		FeatureComplexity:        -1,
		FeatureEntityExtraction:  -1,
		FeatureRecurringDetection: -1,
		FeatureAutoGroup:         -1,
		FeatureDraftEmail:        -1,
		FeatureDraftCalendar:     -1,
	},
}

// AIService handles all AI operations
type AIService struct {
	db      *pgxpool.Pool
	llm     *llm.MultiClient
	configs map[string]string
}

// NewAIService creates a new AI service
func NewAIService(db *pgxpool.Pool, llmClient *llm.MultiClient) *AIService {
	s := &AIService{db: db, llm: llmClient, configs: make(map[string]string)}
	s.loadPromptConfigs()
	return s
}

// loadPromptConfigs loads AI prompt configurations from the shared repository
func (s *AIService) loadPromptConfigs() {
	configs, err := repository.GetAIPromptConfigsAsMap(context.Background())
	if err != nil {
		// Use defaults if loading fails
		s.configs = map[string]string{
			"clean_title_instruction":     "Concise, action-oriented title (max 10 words)",
			"summary_instruction":         "Brief summary if description is long (max 20 words)",
			"complexity_instruction":      "1-10 scale (1=trivial like 'buy milk', 10=complex multi-step project)",
			"due_date_instruction":        "ISO 8601 date if mentioned (e.g., 'tomorrow' = next day, 'next week' = next Monday)",
			"reminder_instruction":        "ISO 8601 datetime if 'remind me' or similar phrase found",
			"entities_instruction":        "person|place|organization",
			"recurrence_instruction":      "RRULE string if recurring pattern detected (e.g., 'every Monday')",
			"suggested_group_instruction": "Category suggestion based on content (e.g., 'Work', 'Shopping', 'Health')",
			"decompose_step_count":        "2-5",
			"decompose_rules":             "Each step should be a single, concrete action\nSteps should be in logical order\nUse action verbs (Call, Send, Research, Write, etc.)\nKeep each step under 10 words",
		}
		return
	}
	s.configs = configs
}

// ReloadConfigs reloads the AI prompt configurations from the database
func (s *AIService) ReloadConfigs() {
	s.loadPromptConfigs()
}

// getConfig returns a config value with a fallback default
func (s *AIService) getConfig(key, defaultValue string) string {
	if val, ok := s.configs[key]; ok && val != "" {
		return val
	}
	return defaultValue
}

// getConfigEscaped returns a config value with JSON-unsafe characters escaped
// Use this when embedding config values inside JSON examples in prompts
func (s *AIService) getConfigEscaped(key, defaultValue string) string {
	val := s.getConfig(key, defaultValue)
	return escapeForJSONPrompt(val)
}

// escapeForJSONPrompt escapes characters that could break JSON structure in prompts
func escapeForJSONPrompt(s string) string {
	// Escape backslashes first, then quotes
	s = strings.ReplaceAll(s, `\`, `\\`)
	s = strings.ReplaceAll(s, `"`, `\"`)
	return s
}

// AIProcessResult contains all AI processing results
type AIProcessResult struct {
	CleanedTitle   *string       `json:"cleaned_title,omitempty"`
	CleanedDesc    *string       `json:"cleaned_description,omitempty"`
	Summary        *string       `json:"summary,omitempty"`
	DueAt          *time.Time    `json:"due_date,omitempty"` // JSON uses due_date (AI response format)
	HasDueTime     bool          `json:"has_due_time"`       // true if AI detected specific time
	ReminderTime   *time.Time    `json:"reminder_time,omitempty"`
	Complexity     *int          `json:"complexity,omitempty"`
	Entities       []Entity      `json:"entities,omitempty"`
	RecurrenceRule *string       `json:"recurrence_rule,omitempty"`
	SuggestedGroup *string       `json:"suggested_group,omitempty"`
	Steps          []TaskStep    `json:"steps,omitempty"`
	Draft          *DraftContent `json:"draft,omitempty"`
}

// Entity represents an extracted entity
type Entity struct {
	Type  string `json:"type"`  // person, place, organization, date, etc.
	Value string `json:"value"`
	Start int    `json:"start"` // position in text
	End   int    `json:"end"`
}

// TaskStep represents a decomposed step
type TaskStep struct {
	Step   int    `json:"step"`
	Action string `json:"action"`
	Done   bool   `json:"done"`
}

// DraftContent represents an email or calendar draft
type DraftContent struct {
	Type      string   `json:"type"` // email or calendar
	To        string   `json:"to,omitempty"`
	Subject   string   `json:"subject,omitempty"`
	Body      string   `json:"body,omitempty"`
	Title     string   `json:"title,omitempty"`
	StartTime string   `json:"start_time,omitempty"`
	EndTime   string   `json:"end_time,omitempty"`
	Attendees []string `json:"attendees,omitempty"`
}

// GetUserTier retrieves the user's subscription tier from the shared repository
func (s *AIService) GetUserTier(ctx context.Context, userID uuid.UUID) (UserTier, error) {
	tier, err := repository.GetUserTier(ctx, userID)
	if err != nil {
		// Default to free if error
		return TierFree, nil
	}
	return UserTier(tier), nil
}

// CheckAndIncrementUsage checks if user can use a feature and increments counter
func (s *AIService) CheckAndIncrementUsage(ctx context.Context, userID uuid.UUID, feature AIFeature) (bool, error) {
	tier, err := s.GetUserTier(ctx, userID)
	if err != nil {
		return false, err
	}

	// Check if feature is available for this tier
	limits, ok := featureLimits[tier]
	if !ok {
		return false, fmt.Errorf("unknown tier: %s", tier)
	}

	limit, ok := limits[feature]
	if !ok {
		return false, nil // Feature not available for this tier
	}

	// Unlimited
	if limit == -1 {
		// Still track usage for analytics
		s.incrementUsage(ctx, userID, feature)
		return true, nil
	}

	// Check current usage
	var currentCount int
	err = s.db.QueryRow(ctx,
		`SELECT COALESCE(count, 0) FROM ai_usage
		 WHERE user_id = $1 AND feature = $2 AND used_at = CURRENT_DATE`,
		userID, feature,
	).Scan(&currentCount)

	if err != nil {
		currentCount = 0
	}

	if currentCount >= limit {
		return false, nil // Limit reached
	}

	// Increment usage
	s.incrementUsage(ctx, userID, feature)
	return true, nil
}

func (s *AIService) incrementUsage(ctx context.Context, userID uuid.UUID, feature AIFeature) {
	_, _ = s.db.Exec(ctx,
		`INSERT INTO ai_usage (user_id, feature, used_at, count)
		 VALUES ($1, $2, CURRENT_DATE, 1)
		 ON CONFLICT (user_id, feature, used_at)
		 DO UPDATE SET count = ai_usage.count + 1`,
		userID, feature,
	)
}

// ProcessTaskOnSave runs all auto-triggered AI features on task save
func (s *AIService) ProcessTaskOnSave(ctx context.Context, userID uuid.UUID, taskID uuid.UUID, title, description string) (*AIProcessResult, error) {
	if s.llm == nil {
		return nil, fmt.Errorf("AI service not available")
	}

	tier, _ := s.GetUserTier(ctx, userID)
	result := &AIProcessResult{}

	// Build combined prompt for efficiency (one API call for multiple features)
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

	// Parse response
	if err := s.parseAutoProcessResponse(resp.Content, result); err != nil {
		return nil, err
	}

	// Track usage for each feature processed
	s.trackAutoProcessUsage(ctx, userID, tier, result)

	return result, nil
}

func (s *AIService) buildAutoProcessPrompt(tier UserTier, title, description string) string {
	today := time.Now().Format("2006-01-02")
	dayOfWeek := time.Now().Weekday().String()

	// Get configurable instructions (escaped for safe JSON embedding)
	cleanTitleInstr := s.getConfigEscaped("clean_title_instruction", "Concise, action-oriented title (max 10 words)")
	summaryInstr := s.getConfigEscaped("summary_instruction", "Brief summary if description is long (max 20 words)")
	dueDateInstr := s.getConfigEscaped("due_date_instruction", "ISO 8601 date if mentioned (e.g., 'tomorrow' = next day, 'next week' = next Monday)")
	reminderInstr := s.getConfigEscaped("reminder_instruction", "ISO 8601 datetime if 'remind me' or similar phrase found")
	complexityInstr := s.getConfigEscaped("complexity_instruction", "1-10 scale (1=trivial like 'buy milk', 10=complex multi-step project)")

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

	// Add tier-specific features
	if tier == TierLight || tier == TierPremium {
		entitiesInstr := s.getConfigEscaped("entities_instruction", "person|place|organization")
		recurrenceInstr := s.getConfigEscaped("recurrence_instruction", "RRULE string if recurring pattern detected (e.g., 'every Monday')")
		suggestedGroupInstr := s.getConfigEscaped("suggested_group_instruction", "Category suggestion based on content (e.g., 'Work', 'Shopping', 'Health')")

		basePrompt += fmt.Sprintf(`,
  "entities": [{"type": "%s", "value": "extracted value"}],
  "recurrence_rule": "%s",
  "suggested_group": "%s"`, entitiesInstr, recurrenceInstr, suggestedGroupInstr)
	}

	// Check for draft triggers
	if tier == TierLight || tier == TierPremium {
		if s.containsDraftTrigger(title + " " + description) {
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

func (s *AIService) containsDraftTrigger(text string) bool {
	text = strings.ToLower(text)
	triggers := []string{
		"email", "tell ", "message ", "contact ",
		"meet with", "meeting", "schedule ", "call with",
	}
	for _, trigger := range triggers {
		if strings.Contains(text, trigger) {
			return true
		}
	}
	return false
}

func (s *AIService) parseAutoProcessResponse(content string, result *AIProcessResult) error {
	// Extract JSON from response (handle markdown code blocks)
	content = strings.TrimSpace(content)
	if strings.HasPrefix(content, "```") {
		// Remove markdown code block
		re := regexp.MustCompile("```(?:json)?\\s*([\\s\\S]*?)\\s*```")
		matches := re.FindStringSubmatch(content)
		if len(matches) > 1 {
			content = matches[1]
		}
	}

	var parsed struct {
		CleanedTitle   string   `json:"cleaned_title"`
		Summary        string   `json:"summary"`
		DueDate        string   `json:"due_date"`
		ReminderTime   string   `json:"reminder_time"`
		Complexity     int      `json:"complexity"`
		Entities       []Entity `json:"entities"`
		RecurrenceRule string   `json:"recurrence_rule"`
		SuggestedGroup string   `json:"suggested_group"`
		Draft          *DraftContent `json:"draft"`
	}

	if err := json.Unmarshal([]byte(content), &parsed); err != nil {
		return fmt.Errorf("failed to parse AI response: %w", err)
	}

	if parsed.CleanedTitle != "" {
		// Post-process: remove trailing period (not suitable for todo list titles)
		cleanedTitle := strings.TrimSuffix(parsed.CleanedTitle, ".")
		result.CleanedTitle = &cleanedTitle
	}
	if parsed.Summary != "" {
		result.Summary = &parsed.Summary
	}
	if parsed.DueDate != "" {
		if t, err := time.Parse(time.RFC3339, parsed.DueDate); err == nil {
			result.DueAt = &t
			// RFC3339 format includes time, so HasDueTime = true
			result.HasDueTime = true
		} else if t, err := time.Parse("2006-01-02", parsed.DueDate); err == nil {
			result.DueAt = &t
			// Date-only format, so HasDueTime = false
			result.HasDueTime = false
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

func (s *AIService) trackAutoProcessUsage(ctx context.Context, userID uuid.UUID, tier UserTier, result *AIProcessResult) {
	if result.CleanedTitle != nil {
		s.incrementUsage(ctx, userID, FeatureCleanTitle)
	}
	if result.Summary != nil {
		s.incrementUsage(ctx, userID, FeatureCleanDescription)
	}
	if result.DueAt != nil {
		s.incrementUsage(ctx, userID, FeatureSmartDueDate)
	}
	if result.ReminderTime != nil {
		s.incrementUsage(ctx, userID, FeatureReminder)
	}
	if tier != TierFree {
		if result.Complexity != nil {
			s.incrementUsage(ctx, userID, FeatureComplexity)
		}
		if len(result.Entities) > 0 {
			s.incrementUsage(ctx, userID, FeatureEntityExtraction)
		}
		if result.RecurrenceRule != nil {
			s.incrementUsage(ctx, userID, FeatureRecurringDetection)
		}
		if result.SuggestedGroup != nil {
			s.incrementUsage(ctx, userID, FeatureAutoGroup)
		}
		if result.Draft != nil {
			if result.Draft.Type == "email" {
				s.incrementUsage(ctx, userID, FeatureDraftEmail)
			} else {
				s.incrementUsage(ctx, userID, FeatureDraftCalendar)
			}
		}
	}
}

// Decompose breaks a task into steps (manual trigger, Light+ only)
func (s *AIService) Decompose(ctx context.Context, userID uuid.UUID, title, description string) ([]TaskStep, error) {
	if s.llm == nil {
		return nil, fmt.Errorf("AI service not available")
	}

	// Check usage limit
	canUse, err := s.CheckAndIncrementUsage(ctx, userID, FeatureDecompose)
	if err != nil {
		return nil, err
	}
	if !canUse {
		return nil, fmt.Errorf("daily limit reached for decompose feature")
	}

	// Get configurable decompose settings
	stepCount := s.getConfig("decompose_step_count", "3-5")
	decomposeRules := s.getConfig("decompose_rules", `Each step should be a single, concrete action
Steps should be in logical order
Use action verbs (Call, Send, Research, Write, etc.)
Keep each step under 10 words`)

	// Format rules as bullet points
	ruleLines := strings.Split(decomposeRules, "\n")
	formattedRules := ""
	for _, rule := range ruleLines {
		rule = strings.TrimSpace(rule)
		if rule != "" {
			formattedRules += "- " + rule + "\n"
		}
	}

	descPart := ""
	if description != "" {
		descPart = "Description: " + description
	}

	// First attempt
	steps, err := s.decomposeWithPrompt(ctx, title, descPart, stepCount, formattedRules, false)
	if err != nil {
		return nil, err
	}

	// Post-process: if more than 5 steps, retry with strict MAX = 5
	if len(steps) > 5 {
		steps, err = s.decomposeWithPrompt(ctx, title, descPart, "exactly 5", formattedRules, true)
		if err != nil {
			return nil, err
		}
		// Truncate if still over 5
		if len(steps) > 5 {
			steps = steps[:5]
		}
	}

	return steps, nil
}

// decomposeWithPrompt is a helper that calls the LLM with the decompose prompt
func (s *AIService) decomposeWithPrompt(ctx context.Context, title, descPart, stepCount, formattedRules string, strict bool) ([]TaskStep, error) {
	strictNote := ""
	if strict {
		strictNote = "\n\nIMPORTANT: You MUST return MAXIMUM 5 steps. No more than 5. Combine steps if needed."
	}

	prompt := fmt.Sprintf(`Break down this task into %s actionable steps. MAXIMUM 5 steps allowed.

Task: %s
%s

Return ONLY a JSON array:
[
  {"step": 1, "action": "First specific action", "done": false},
  {"step": 2, "action": "Second specific action", "done": false}
]

Rules:
%s%s`, stepCount, title, descPart, formattedRules, strictNote)

	resp, err := s.llm.Complete(ctx, llm.CompletionRequest{
		Messages: []llm.Message{
			{Role: "user", Content: prompt},
		},
		MaxTokens:   500,
		Temperature: 0.3,
	})

	if err != nil {
		return nil, fmt.Errorf("AI decompose failed: %w", err)
	}

	// Parse response
	content := strings.TrimSpace(resp.Content)
	if strings.HasPrefix(content, "```") {
		re := regexp.MustCompile("```(?:json)?\\s*([\\s\\S]*?)\\s*```")
		matches := re.FindStringSubmatch(content)
		if len(matches) > 1 {
			content = matches[1]
		}
	}

	var steps []TaskStep
	if err := json.Unmarshal([]byte(content), &steps); err != nil {
		return nil, fmt.Errorf("failed to parse steps: %w", err)
	}

	return steps, nil
}

// GetUsageStats returns current usage stats for a user
func (s *AIService) GetUsageStats(ctx context.Context, userID uuid.UUID) (map[string]interface{}, error) {
	tier, _ := s.GetUserTier(ctx, userID)

	rows, err := s.db.Query(ctx,
		`SELECT feature, count FROM ai_usage
		 WHERE user_id = $1 AND used_at = CURRENT_DATE`,
		userID,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	usage := make(map[string]int)
	for rows.Next() {
		var feature string
		var count int
		if err := rows.Scan(&feature, &count); err != nil {
			continue
		}
		usage[feature] = count
	}

	limits := featureLimits[tier]
	stats := map[string]interface{}{
		"tier":   tier,
		"usage":  usage,
		"limits": limits,
	}

	return stats, nil
}

// SaveDraft stores an AI-generated draft
func (s *AIService) SaveDraft(ctx context.Context, userID, taskID uuid.UUID, draft *DraftContent) (uuid.UUID, error) {
	var draftID uuid.UUID
	contentJSON, _ := json.Marshal(draft)

	err := s.db.QueryRow(ctx,
		`INSERT INTO ai_drafts (user_id, task_id, draft_type, content)
		 VALUES ($1, $2, $3, $4)
		 RETURNING id`,
		userID, taskID, draft.Type, contentJSON,
	).Scan(&draftID)

	return draftID, err
}

// GetPendingDrafts retrieves pending drafts for a user
func (s *AIService) GetPendingDrafts(ctx context.Context, userID uuid.UUID) ([]map[string]interface{}, error) {
	rows, err := s.db.Query(ctx,
		`SELECT id, task_id, draft_type, content, created_at
		 FROM ai_drafts
		 WHERE user_id = $1 AND status = 'draft'
		 ORDER BY created_at DESC`,
		userID,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var drafts []map[string]interface{}
	for rows.Next() {
		var id, taskID uuid.UUID
		var draftType string
		var content []byte
		var createdAt time.Time

		if err := rows.Scan(&id, &taskID, &draftType, &content, &createdAt); err != nil {
			continue
		}

		var contentMap map[string]interface{}
		_ = json.Unmarshal(content, &contentMap)

		drafts = append(drafts, map[string]interface{}{
			"id":         id,
			"task_id":    taskID,
			"type":       draftType,
			"content":    contentMap,
			"created_at": createdAt,
		})
	}

	return drafts, nil
}
