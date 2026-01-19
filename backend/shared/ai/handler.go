package ai

import (
	"encoding/json"
	"fmt"
	"strings"
	"time"

	"github.com/gofiber/fiber/v2"
	"github.com/google/uuid"
	"github.com/csaptu/flow/pkg/httputil"
	"github.com/csaptu/flow/pkg/llm"
	"github.com/csaptu/flow/pkg/middleware"
	"github.com/csaptu/flow/shared/repository"
)

// Handler handles AI endpoints
type Handler struct {
	service *Service
}

// NewHandler creates a new AI handler
func NewHandler(llmClient *llm.MultiClient) *Handler {
	return &Handler{
		service: NewService(llmClient),
	}
}

// TaskResponse represents a task in API responses
type TaskResponse struct {
	ID                    string   `json:"id"`
	Title                 string   `json:"title"`
	OriginalTitle         *string  `json:"original_title,omitempty"`
	AICleanedTitle        bool     `json:"ai_cleaned_title"`
	Description           *string  `json:"description,omitempty"`
	OriginalDescription   *string  `json:"original_description,omitempty"`
	AICleanedDescription  bool     `json:"ai_cleaned_description"`
	AISummary             *string  `json:"ai_summary,omitempty"`
	Status          string   `json:"status"`
	Priority        int      `json:"priority"`
	DueDate         *string  `json:"due_date,omitempty"`
	CompletedAt     *string  `json:"completed_at,omitempty"`
	Tags            []string `json:"tags"`
	ParentID        *string  `json:"parent_id,omitempty"`
	Depth           int      `json:"depth"`
	Complexity      int      `json:"complexity"`
	HasChildren     bool     `json:"has_children"`
	ChildrenCount   int      `json:"children_count"`
	CreatedAt       string   `json:"created_at"`
	UpdatedAt       string   `json:"updated_at"`
}

func toTaskResponse(t *repository.Task, childCount int) TaskResponse {
	resp := TaskResponse{
		ID:                   t.ID.String(),
		Title:                t.Title,
		OriginalTitle:        t.OriginalTitle,
		AICleanedTitle:       t.AICleanedTitle,
		Description:          t.Description,
		OriginalDescription:  t.OriginalDescription,
		AICleanedDescription: t.AICleanedDescription,
		AISummary:            t.AISummary,
		Status:         t.Status,
		Priority:       t.Priority,
		Tags:           t.Tags,
		Depth:          t.Depth,
		Complexity:     t.Complexity,
		HasChildren:    childCount > 0,
		ChildrenCount:  childCount,
		CreatedAt:      t.CreatedAt.Format(time.RFC3339),
		UpdatedAt:      t.UpdatedAt.Format(time.RFC3339),
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

	return resp
}

// AIDecompose breaks down a task into subtasks
func (h *Handler) AIDecompose(c *fiber.Ctx) error {
	if !h.service.IsAvailable() {
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

	task, childCount, err := repository.GetTaskByID(c.Context(), taskID, userID)
	if err != nil {
		return httputil.InternalError(c, "database error")
	}
	if task == nil {
		return httputil.NotFound(c, "task")
	}

	if task.Depth > 0 {
		return httputil.BadRequest(c, "subtasks cannot be further decomposed")
	}

	// Check feature access
	canUse, _ := h.service.CheckAndIncrementUsage(c.Context(), userID, FeatureDecompose)
	if !canUse {
		return httputil.PaymentRequired(c, "Upgrade to Light tier for task decomposition")
	}

	// Get existing subtasks to include in prompt
	existingSubtasks, err := repository.GetSubtasks(c.Context(), taskID, userID)
	if err != nil {
		existingSubtasks = nil // Continue without existing subtasks if error
	}

	// Build prompt with existing subtasks context
	var promptBuilder strings.Builder
	if len(existingSubtasks) > 0 {
		promptBuilder.WriteString(fmt.Sprintf(`Add 2-5 more actionable subtasks to this task.
Task: %s
%s

Existing subtasks:
`, task.Title, func() string {
			if task.Description != nil {
				return "Description: " + *task.Description
			}
			return ""
		}()))
		for _, st := range existingSubtasks {
			promptBuilder.WriteString(fmt.Sprintf("- %s\n", st.Title))
		}
		promptBuilder.WriteString(`
Return ONLY a JSON array of NEW subtask titles (do not include existing ones), like:
["New subtask title 1", "New subtask title 2"]

Each new subtask should be:
- A single, concrete action not already covered by existing subtasks
- In logical order
- Starting with an action verb`)
	} else {
		promptBuilder.WriteString(fmt.Sprintf(`Break down this task into 2-5 actionable subtasks.
Task: %s
%s

Return ONLY a JSON array of subtask titles, like:
["First subtask title", "Second subtask title", "Third subtask title"]

Each subtask should be:
- A single, concrete action
- In logical order
- Starting with an action verb`, task.Title, func() string {
			if task.Description != nil {
				return "Description: " + *task.Description
			}
			return ""
		}()))
	}

	resp, err := h.service.LLM().Complete(c.Context(), llm.CompletionRequest{
		Messages: []llm.Message{
			{Role: "user", Content: promptBuilder.String()},
		},
		MaxTokens:   500,
		Temperature: 0.3,
	})
	if err != nil {
		return httputil.ServiceUnavailable(c, "AI service error")
	}

	var subtaskTitles []string
	content := strings.TrimSpace(resp.Content)
	if strings.HasPrefix(content, "```") {
		lines := strings.Split(content, "\n")
		var jsonLines []string
		inBlock := false
		for _, line := range lines {
			if strings.HasPrefix(line, "```") {
				inBlock = !inBlock
				continue
			}
			if inBlock {
				jsonLines = append(jsonLines, line)
			}
		}
		content = strings.Join(jsonLines, "\n")
	}

	if err := json.Unmarshal([]byte(content), &subtaskTitles); err != nil {
		return httputil.InternalError(c, "failed to parse AI response")
	}

	// Create subtasks and collect the created ones
	createdSubtasks := make([]TaskResponse, 0) // Initialize as empty slice, not nil
	startOrder := len(existingSubtasks)        // Start ordering after existing subtasks
	for i, title := range subtaskTitles {
		title = strings.TrimSpace(title)
		if title == "" {
			continue
		}
		subtaskID, err := repository.CreateSubtask(c.Context(), userID, taskID, title, startOrder+i)
		if err == nil {
			// Get the created subtask to return it
			subtask, _, _ := repository.GetTaskByID(c.Context(), subtaskID, userID)
			if subtask != nil {
				createdSubtasks = append(createdSubtasks, toTaskResponse(subtask, 0))
			}
		}
	}

	return httputil.Success(c, map[string]interface{}{
		"task":     toTaskResponse(task, childCount+len(createdSubtasks)),
		"subtasks": createdSubtasks,
	})
}

// AIClean cleans up a task title and description
func (h *Handler) AIClean(c *fiber.Ctx) error {
	if !h.service.IsAvailable() {
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

	task, childCount, err := repository.GetTaskByID(c.Context(), taskID, userID)
	if err != nil {
		return httputil.InternalError(c, "database error")
	}
	if task == nil {
		return httputil.NotFound(c, "task")
	}

	// Build prompt based on what fields have content
	hasDescription := task.Description != nil && *task.Description != ""

	var prompt string
	if hasDescription {
		prompt = fmt.Sprintf(`Fix spelling and grammar in this task title and description. Use simple words (a 10 year old should understand).

RULES:
1. Keep the SAME meaning - don't change what the task is about
2. If already clear and correct, return UNCHANGED
3. Use simple everyday words, not fancy/academic words
4. Title: max 10 words, NO period at the end, lowercase unless proper noun
5. DO NOT change: names, emails, URLs, code, numbers, dates
6. DO NOT add info that wasn't there
7. DO NOT add filler words like "a", "the", "dish" - keep it minimal
8. Short descriptions (1-3 words) usually need no changes

Original title: %s
Original description: %s

Return ONLY this JSON format:
{"title": "cleaned or original title", "title_changed": true/false, "description": "cleaned or original description", "description_changed": true/false}

Set _changed to false if no changes needed. Return original text when not changing.`,
			task.Title, *task.Description)
	} else {
		prompt = fmt.Sprintf(`Fix spelling and grammar in this task title. Use simple words (a 10 year old should understand).

RULES:
1. Keep the SAME meaning - don't change what the task is about
2. If already clear and correct, return UNCHANGED
3. Use simple everyday words, not fancy/academic words
4. Max 10 words, NO period at the end, lowercase unless proper noun
5. DO NOT change: names, emails, URLs, code, numbers, dates
6. DO NOT add filler words like "a", "the", "dish" - keep it minimal

Original title: %s

Return ONLY this JSON format:
{"title": "cleaned or original title", "title_changed": true/false}

Set title_changed to false if no changes needed.`,
			task.Title)
	}

	resp, err := h.service.LLM().Complete(c.Context(), llm.CompletionRequest{
		Messages: []llm.Message{
			{Role: "user", Content: prompt},
		},
		MaxTokens:   500,
		Temperature: 0.1, // Lower temperature for more consistent output
	})
	if err != nil {
		return httputil.ServiceUnavailable(c, "AI service error")
	}

	// Try to parse JSON, handle potential formatting issues
	content := strings.TrimSpace(resp.Content)
	// Remove markdown code blocks if present
	if strings.HasPrefix(content, "```") {
		lines := strings.Split(content, "\n")
		var jsonLines []string
		inBlock := false
		for _, line := range lines {
			if strings.HasPrefix(line, "```") {
				inBlock = !inBlock
				continue
			}
			if inBlock {
				jsonLines = append(jsonLines, line)
			}
		}
		content = strings.Join(jsonLines, "\n")
	}

	var cleaned struct {
		Title              string `json:"title"`
		TitleChanged       bool   `json:"title_changed"`
		Description        string `json:"description"`
		DescriptionChanged bool   `json:"description_changed"`
		Changed            bool   `json:"changed"` // Legacy field for backwards compatibility
	}
	if err := json.Unmarshal([]byte(content), &cleaned); err != nil {
		// If JSON parsing fails, just keep the original
		return httputil.Success(c, toTaskResponse(task, childCount))
	}

	// Handle legacy "changed" field (for backwards compatibility with title-only clean)
	if cleaned.Changed && !cleaned.TitleChanged {
		cleaned.TitleChanged = cleaned.Changed
	}

	// Only update if AI actually changed something meaningful
	updates := map[string]interface{}{}

	// Validate title change - reject if too different (AI might be hallucinating)
	if cleaned.TitleChanged && cleaned.Title != "" && cleaned.Title != task.Title {
		// Basic sanity check: new title shouldn't be wildly different in length
		lenDiff := len(cleaned.Title) - len(task.Title)
		if lenDiff < 0 {
			lenDiff = -lenDiff
		}
		// Allow change if length difference is reasonable (not more than 2x or adding 50+ chars)
		if lenDiff < len(task.Title) && lenDiff < 50 {
			updates["title"] = cleaned.Title
			updates["original_title"] = task.Title
			updates["ai_cleaned_title"] = true
		}
	}

	// Validate description change
	if cleaned.DescriptionChanged && cleaned.Description != "" {
		currentDesc := ""
		if task.Description != nil {
			currentDesc = *task.Description
		}
		if cleaned.Description != currentDesc {
			// Basic sanity check for description too
			lenDiff := len(cleaned.Description) - len(currentDesc)
			if lenDiff < 0 {
				lenDiff = -lenDiff
			}
			// Allow change if length difference is reasonable
			if lenDiff < len(currentDesc)+50 && lenDiff < 200 {
				updates["description"] = cleaned.Description
				updates["original_description"] = currentDesc
				updates["ai_cleaned_description"] = true
			}
		}
	}

	// Only update DB if there are changes
	if len(updates) == 0 {
		return httputil.Success(c, toTaskResponse(task, childCount))
	}

	if err := repository.UpdateTaskAIFields(c.Context(), taskID, userID, updates); err != nil {
		return httputil.InternalError(c, "failed to update task")
	}

	// Refresh task data
	task, childCount, _ = repository.GetTaskByID(c.Context(), taskID, userID)
	return httputil.Success(c, toTaskResponse(task, childCount))
}

// AIRevert reverts AI-cleaned title and/or description back to the original human-written version
func (h *Handler) AIRevert(c *fiber.Ctx) error {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		return httputil.Unauthorized(c, "")
	}

	taskID, err := uuid.Parse(c.Params("id"))
	if err != nil {
		return httputil.BadRequest(c, "invalid task ID")
	}

	task, childCount, err := repository.GetTaskByID(c.Context(), taskID, userID)
	if err != nil {
		return httputil.InternalError(c, "database error")
	}
	if task == nil {
		return httputil.NotFound(c, "task")
	}

	// Check if there's anything to revert
	hasOriginalTitle := task.OriginalTitle != nil && *task.OriginalTitle != ""
	hasOriginalDescription := task.OriginalDescription != nil && *task.OriginalDescription != ""

	if !hasOriginalTitle && !hasOriginalDescription {
		return httputil.BadRequest(c, "no original content to revert to")
	}

	// Revert to original values
	updates := map[string]interface{}{}

	if hasOriginalTitle {
		updates["title"] = *task.OriginalTitle
		updates["original_title"] = nil // Clear the original
		updates["ai_cleaned_title"] = false
	}

	if hasOriginalDescription {
		updates["description"] = *task.OriginalDescription
		updates["original_description"] = nil // Clear the original
		updates["ai_cleaned_description"] = false
	}

	if err := repository.UpdateTaskAIFields(c.Context(), taskID, userID, updates); err != nil {
		return httputil.InternalError(c, "failed to revert task")
	}

	// Refresh task data
	task, childCount, _ = repository.GetTaskByID(c.Context(), taskID, userID)
	return httputil.Success(c, toTaskResponse(task, childCount))
}

// AIRate rates the complexity of a task
func (h *Handler) AIRate(c *fiber.Ctx) error {
	if !h.service.IsAvailable() {
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

	task, childCount, err := repository.GetTaskByID(c.Context(), taskID, userID)
	if err != nil {
		return httputil.InternalError(c, "database error")
	}
	if task == nil {
		return httputil.NotFound(c, "task")
	}

	canUse, _ := h.service.CheckAndIncrementUsage(c.Context(), userID, FeatureComplexity)
	if !canUse {
		return httputil.PaymentRequired(c, "Upgrade to Light tier for complexity rating")
	}

	prompt := fmt.Sprintf(`Rate the complexity of this task on a scale of 1-10.

Task: %s
%s

Rating scale:
1-2: Trivial (e.g., "buy milk", "send text")
3-4: Simple (e.g., "schedule meeting", "write short email")
5-6: Moderate (e.g., "prepare presentation", "review document")
7-8: Complex (e.g., "design feature", "plan event")
9-10: Very complex (e.g., "launch product", "migrate system")

Return ONLY a JSON object:
{"complexity": <number 1-10>, "reason": "Brief explanation (max 15 words)"}`,
		task.Title, func() string {
			if task.Description != nil {
				return "Description: " + *task.Description
			}
			return ""
		}())

	resp, err := h.service.LLM().Complete(c.Context(), llm.CompletionRequest{
		Messages: []llm.Message{
			{Role: "user", Content: prompt},
		},
		MaxTokens:   100,
		Temperature: 0.3,
	})
	if err != nil {
		return httputil.ServiceUnavailable(c, "AI service error")
	}

	var rated struct {
		Complexity int    `json:"complexity"`
		Reason     string `json:"reason"`
	}
	if err := json.Unmarshal([]byte(resp.Content), &rated); err != nil {
		return httputil.InternalError(c, "failed to parse AI response")
	}

	updates := map[string]interface{}{
		"complexity": rated.Complexity,
	}
	if err := repository.UpdateTaskAIFields(c.Context(), taskID, userID, updates); err != nil {
		return httputil.InternalError(c, "failed to update task")
	}

	task, childCount, _ = repository.GetTaskByID(c.Context(), taskID, userID)
	return httputil.Success(c, map[string]interface{}{
		"task":       toTaskResponse(task, childCount),
		"complexity": rated.Complexity,
		"reason":     rated.Reason,
	})
}

// AIExtract extracts entities from a task
func (h *Handler) AIExtract(c *fiber.Ctx) error {
	if !h.service.IsAvailable() {
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

	task, childCount, err := repository.GetTaskByID(c.Context(), taskID, userID)
	if err != nil {
		return httputil.InternalError(c, "database error")
	}
	if task == nil {
		return httputil.NotFound(c, "task")
	}

	canUse, _ := h.service.CheckAndIncrementUsage(c.Context(), userID, FeatureEntityExtraction)
	if !canUse {
		return httputil.PaymentRequired(c, "Upgrade to Light tier for entity extraction")
	}

	prompt := fmt.Sprintf(`Extract key entities from this task.

Task: %s
%s

Return ONLY a JSON object:
{
  "entities": [
    {"type": "person", "value": "name"},
    {"type": "date", "value": "parsed date"},
    {"type": "location", "value": "place"},
    {"type": "organization", "value": "company name"},
    {"type": "email", "value": "email@example.com"},
    {"type": "phone", "value": "+1234567890"}
  ]
}

Only include entities that are actually present. Leave array empty if none found.`,
		task.Title, func() string {
			if task.Description != nil {
				return "Description: " + *task.Description
			}
			return ""
		}())

	resp, err := h.service.LLM().Complete(c.Context(), llm.CompletionRequest{
		Messages: []llm.Message{
			{Role: "user", Content: prompt},
		},
		MaxTokens:   300,
		Temperature: 0.2,
	})
	if err != nil {
		return httputil.ServiceUnavailable(c, "AI service error")
	}

	var extracted struct {
		Entities []Entity `json:"entities"`
	}
	if err := json.Unmarshal([]byte(resp.Content), &extracted); err != nil {
		return httputil.InternalError(c, "failed to parse AI response")
	}

	entitiesJSON, _ := json.Marshal(extracted.Entities)
	updates := map[string]interface{}{
		"ai_entities": entitiesJSON,
	}
	if err := repository.UpdateTaskAIFields(c.Context(), taskID, userID, updates); err != nil {
		return httputil.InternalError(c, "failed to update task")
	}

	task, childCount, _ = repository.GetTaskByID(c.Context(), taskID, userID)
	return httputil.Success(c, map[string]interface{}{
		"task":     toTaskResponse(task, childCount),
		"entities": extracted.Entities,
	})
}

// AIRemind suggests a reminder time for a task
func (h *Handler) AIRemind(c *fiber.Ctx) error {
	if !h.service.IsAvailable() {
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

	task, childCount, err := repository.GetTaskByID(c.Context(), taskID, userID)
	if err != nil {
		return httputil.InternalError(c, "database error")
	}
	if task == nil {
		return httputil.NotFound(c, "task")
	}

	canUse, _ := h.service.CheckAndIncrementUsage(c.Context(), userID, FeatureReminder)
	if !canUse {
		return httputil.PaymentRequired(c, "Upgrade to Premium tier for smart reminders")
	}

	now := time.Now()
	dueInfo := ""
	if task.DueDate != nil {
		dueInfo = fmt.Sprintf("Due date: %s", task.DueDate.Format("2006-01-02 15:04"))
	}

	prompt := fmt.Sprintf(`Suggest an appropriate reminder time for this task.

Task: %s
%s
%s
Current time: %s

Return ONLY a JSON object:
{"reminder_time": "ISO 8601 datetime", "reason": "Brief explanation (max 15 words)"}

Guidelines:
- Suggest time that gives enough prep time before any deadlines
- Consider task complexity and urgency
- Default to morning (9 AM) for general tasks
- For meetings, suggest 1 day before and 1 hour before`,
		task.Title, func() string {
			if task.Description != nil {
				return "Description: " + *task.Description
			}
			return ""
		}(), dueInfo, now.Format(time.RFC3339))

	resp, err := h.service.LLM().Complete(c.Context(), llm.CompletionRequest{
		Messages: []llm.Message{
			{Role: "user", Content: prompt},
		},
		MaxTokens:   150,
		Temperature: 0.3,
	})
	if err != nil {
		return httputil.ServiceUnavailable(c, "AI service error")
	}

	var suggested struct {
		ReminderTime string `json:"reminder_time"`
		Reason       string `json:"reason"`
	}
	if err := json.Unmarshal([]byte(resp.Content), &suggested); err != nil {
		return httputil.InternalError(c, "failed to parse AI response")
	}

	reminderTime, err := time.Parse(time.RFC3339, suggested.ReminderTime)
	if err != nil {
		reminderTime, err = time.Parse("2006-01-02T15:04:05", suggested.ReminderTime)
		if err != nil {
			return httputil.InternalError(c, "invalid reminder time from AI")
		}
	}

	updates := map[string]interface{}{
		"reminder_at": reminderTime,
	}
	if err := repository.UpdateTaskAIFields(c.Context(), taskID, userID, updates); err != nil {
		return httputil.InternalError(c, "failed to update task")
	}

	task, childCount, _ = repository.GetTaskByID(c.Context(), taskID, userID)
	return httputil.Success(c, map[string]interface{}{
		"task":          toTaskResponse(task, childCount),
		"reminder_time": reminderTime,
		"reason":        suggested.Reason,
	})
}

// AIEmail drafts an email based on the task
func (h *Handler) AIEmail(c *fiber.Ctx) error {
	if !h.service.IsAvailable() {
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

	task, _, err := repository.GetTaskByID(c.Context(), taskID, userID)
	if err != nil {
		return httputil.InternalError(c, "database error")
	}
	if task == nil {
		return httputil.NotFound(c, "task")
	}

	canUse, _ := h.service.CheckAndIncrementUsage(c.Context(), userID, FeatureDraftEmail)
	if !canUse {
		return httputil.PaymentRequired(c, "Upgrade to Premium tier for email drafts")
	}

	prompt := fmt.Sprintf(`Draft a professional email based on this task.

Task: %s
%s

Return ONLY a JSON object:
{
  "to": "recipient if mentioned, otherwise leave empty",
  "subject": "Clear, concise email subject",
  "body": "Professional email body. Be concise but complete. Include greeting and sign-off placeholder."
}`,
		task.Title, func() string {
			if task.Description != nil {
				return "Description: " + *task.Description
			}
			return ""
		}())

	resp, err := h.service.LLM().Complete(c.Context(), llm.CompletionRequest{
		Messages: []llm.Message{
			{Role: "user", Content: prompt},
		},
		MaxTokens:   500,
		Temperature: 0.4,
	})
	if err != nil {
		return httputil.ServiceUnavailable(c, "AI service error")
	}

	var draft DraftContent
	if err := json.Unmarshal([]byte(resp.Content), &draft); err != nil {
		return httputil.InternalError(c, "failed to parse AI response")
	}
	draft.Type = "email"

	draftID, _ := h.service.SaveDraft(c.Context(), userID, taskID, &draft)

	return httputil.Success(c, map[string]interface{}{
		"draft_id": draftID,
		"draft":    draft,
	})
}

// AIInvite drafts a calendar invite based on the task
func (h *Handler) AIInvite(c *fiber.Ctx) error {
	if !h.service.IsAvailable() {
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

	task, _, err := repository.GetTaskByID(c.Context(), taskID, userID)
	if err != nil {
		return httputil.InternalError(c, "database error")
	}
	if task == nil {
		return httputil.NotFound(c, "task")
	}

	canUse, _ := h.service.CheckAndIncrementUsage(c.Context(), userID, FeatureDraftCalendar)
	if !canUse {
		return httputil.PaymentRequired(c, "Upgrade to Premium tier for calendar invites")
	}

	now := time.Now()
	dueInfo := ""
	if task.DueDate != nil {
		dueInfo = fmt.Sprintf("Due/scheduled: %s", task.DueDate.Format("2006-01-02 15:04"))
	}

	prompt := fmt.Sprintf(`Create a calendar event based on this task.

Task: %s
%s
%s
Current time: %s

Return ONLY a JSON object:
{
  "title": "Event title",
  "start_time": "ISO 8601 datetime",
  "end_time": "ISO 8601 datetime",
  "attendees": ["list of attendees if mentioned"],
  "body": "Event description/agenda"
}

Guidelines:
- Default duration is 30 minutes for calls, 1 hour for meetings
- If no time specified, suggest next business day at 10 AM`,
		task.Title, func() string {
			if task.Description != nil {
				return "Description: " + *task.Description
			}
			return ""
		}(), dueInfo, now.Format(time.RFC3339))

	resp, err := h.service.LLM().Complete(c.Context(), llm.CompletionRequest{
		Messages: []llm.Message{
			{Role: "user", Content: prompt},
		},
		MaxTokens:   400,
		Temperature: 0.4,
	})
	if err != nil {
		return httputil.ServiceUnavailable(c, "AI service error")
	}

	var draft DraftContent
	if err := json.Unmarshal([]byte(resp.Content), &draft); err != nil {
		return httputil.InternalError(c, "failed to parse AI response")
	}
	draft.Type = "calendar"

	draftID, _ := h.service.SaveDraft(c.Context(), userID, taskID, &draft)

	return httputil.Success(c, map[string]interface{}{
		"draft_id": draftID,
		"draft":    draft,
	})
}

// GetAIUsage returns AI usage stats for the current user
func (h *Handler) GetAIUsage(c *fiber.Ctx) error {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		return httputil.Unauthorized(c, "")
	}

	stats, err := h.service.GetUsageStats(c.Context(), userID)
	if err != nil {
		return httputil.InternalError(c, "failed to get usage stats")
	}

	return httputil.Success(c, stats)
}

// GetUserTier returns the current user's subscription tier
func (h *Handler) GetUserTier(c *fiber.Ctx) error {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		return httputil.Unauthorized(c, "")
	}

	tier, _ := h.service.GetUserTier(c.Context(), userID)

	return httputil.Success(c, map[string]interface{}{
		"tier":   tier,
		"limits": FeatureLimits[tier],
	})
}

// GetAIDrafts returns pending AI drafts for the current user
func (h *Handler) GetAIDrafts(c *fiber.Ctx) error {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		return httputil.Unauthorized(c, "")
	}

	drafts, err := h.service.GetPendingDrafts(c.Context(), userID)
	if err != nil {
		return httputil.InternalError(c, "failed to get drafts")
	}

	return httputil.Success(c, drafts)
}

// ApproveDraft marks a draft as approved
func (h *Handler) ApproveDraft(c *fiber.Ctx) error {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		return httputil.Unauthorized(c, "")
	}

	draftID, err := uuid.Parse(c.Params("id"))
	if err != nil {
		return httputil.BadRequest(c, "invalid draft ID")
	}

	var req struct {
		Send bool `json:"send"`
	}
	_ = c.BodyParser(&req)

	status := "approved"
	if req.Send {
		status = "sent"
	}

	rowsAffected, err := repository.UpdateAIDraftStatus(c.Context(), draftID, userID, status)
	if err != nil {
		return httputil.InternalError(c, "failed to approve draft")
	}
	if rowsAffected == 0 {
		return httputil.NotFound(c, "draft")
	}

	return httputil.Success(c, map[string]string{"status": "approved"})
}

// DeleteDraft cancels a draft
func (h *Handler) DeleteDraft(c *fiber.Ctx) error {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		return httputil.Unauthorized(c, "")
	}

	draftID, err := uuid.Parse(c.Params("id"))
	if err != nil {
		return httputil.BadRequest(c, "invalid draft ID")
	}

	rowsAffected, err := repository.UpdateAIDraftStatus(c.Context(), draftID, userID, "cancelled")
	if err != nil {
		return httputil.InternalError(c, "failed to delete draft")
	}
	if rowsAffected == 0 {
		return httputil.NotFound(c, "draft")
	}

	return httputil.NoContent(c)
}

// Service returns the underlying AI service (for use by other handlers)
func (h *Handler) Service() *Service {
	return h.service
}
