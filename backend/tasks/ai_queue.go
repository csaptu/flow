package tasks

import (
	"context"
	"encoding/json"
	"fmt"
	"sync"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/v9"
	"github.com/csaptu/flow/pkg/llm"
	ws "github.com/csaptu/flow/pkg/websocket"
	"github.com/csaptu/flow/shared/repository"
	"github.com/csaptu/flow/tasks/models"
)

// AIFeatureType represents different AI processing features
type AIFeatureType string

const (
	AIFeatureCleanTitle        AIFeatureType = "clean_title"
	AIFeatureCleanDescription  AIFeatureType = "clean_description"
	AIFeatureEntityExtraction  AIFeatureType = "entity_extraction"
	AIFeatureDuplicateCheck    AIFeatureType = "duplicate_check"
	AIFeatureDecompose         AIFeatureType = "decompose"
	AIFeatureComplexity        AIFeatureType = "complexity"
	AIFeatureDueDate           AIFeatureType = "due_date"
)

// TaskSnapshot holds the state of a task at the time AI processing was triggered
// This is kept in-memory during the goroutine's lifetime (typically 2-5 seconds)
type TaskSnapshot struct {
	TaskID               uuid.UUID
	UserID               uuid.UUID
	Title                string
	Description          *string
	AICleanedTitle       *string
	AICleanedDescription *string
	CapturedAt           time.Time
}

// AIQueueResult holds the results from AI processing
type AIQueueResult struct {
	CleanedTitle   *string
	CleanedDesc    *string
	Entities       []Entity
	Complexity     *int
	DueAt          *time.Time
	HasDueTime     bool
	Duplicates     []string
	Subtasks       []TaskStep
	ProcessedFeatures []AIFeatureType
}

// AIProcessor handles queue-based AI processing with conflict detection
type AIProcessor struct {
	db        *pgxpool.Pool
	redis     *redis.Client
	llm       *llm.MultiClient
	aiService *AIService
	mu        sync.Mutex
}

// NewAIProcessor creates a new AI processor
func NewAIProcessor(db *pgxpool.Pool, redis *redis.Client, llmClient *llm.MultiClient) *AIProcessor {
	return &AIProcessor{
		db:        db,
		redis:     redis,
		llm:       llmClient,
		aiService: NewAIService(db, llmClient),
	}
}

// ProcessTaskAI runs AI processing with conflict detection
// This is called asynchronously after task creation/update
func (p *AIProcessor) ProcessTaskAI(ctx context.Context, userID, taskID uuid.UUID) {
	fmt.Printf("[AI Queue] ProcessTaskAI called for task %s, user %s\n", taskID, userID)

	if p.llm == nil {
		fmt.Printf("[AI Queue] LLM client is nil, skipping AI processing\n")
		return
	}
	if p.aiService == nil {
		fmt.Printf("[AI Queue] AI service is nil, skipping AI processing\n")
		return
	}

	// Use a fresh context with timeout since the original may be cancelled
	bgCtx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	// 1. Get current task and create snapshot
	task, err := p.getTask(bgCtx, taskID, userID)
	if err != nil || task == nil {
		return
	}

	snapshot := TaskSnapshot{
		TaskID:               taskID,
		UserID:               userID,
		Title:                task.Title,
		Description:          task.Description,
		AICleanedTitle:       task.AICleanedTitle,
		AICleanedDescription: task.AICleanedDescription,
		CapturedAt:           time.Now(),
	}

	// 2. Get user's tier (for feature access)
	tier, _ := p.aiService.GetUserTier(bgCtx, userID)

	// 3. Get user's AI preferences
	prefs := AIPreferences{}
	if userPrefs, err := repository.GetUserAIPreferencesMap(bgCtx, userID); err == nil && userPrefs != nil {
		prefs = userPrefs
	}
	fmt.Printf("[AI Queue] User preferences: %v\n", prefs)

	// 4. Determine which features to run based on tier and preferences
	featuresToRun := p.determineFeatures(tier, task, prefs)
	fmt.Printf("[AI Queue] Features to run: %v\n", featuresToRun)
	if len(featuresToRun) == 0 {
		fmt.Printf("[AI Queue] No features to run, skipping\n")
		return
	}

	// 4. Run AI processing (all features in one call for efficiency)
	description := ""
	if task.Description != nil {
		description = *task.Description
	}

	result, err := p.aiService.ProcessTaskOnSave(bgCtx, userID, taskID, task.Title, description)
	if err != nil {
		fmt.Printf("[AI Queue] Processing failed for task %s: %v\n", taskID, err)
		return
	}

	// 5. Convert result to queue result
	queueResult := p.convertToQueueResult(result, featuresToRun)

	// 6. Check for conflicts and write results
	p.writeResultsWithConflictCheck(bgCtx, taskID, userID, snapshot, queueResult)
}

// getTask retrieves a task from the database
func (p *AIProcessor) getTask(ctx context.Context, taskID, userID uuid.UUID) (*models.Task, error) {
	var task models.Task
	var tagsJSON, entitiesJSON, duplicateOfJSON []byte
	var dueAt, completedAt *time.Time

	err := p.db.QueryRow(ctx,
		`SELECT id, user_id, title, description, ai_cleaned_title, ai_cleaned_description,
		        status, priority, due_at, has_due_time, completed_at, tags,
		        parent_id, depth, sort_order, complexity, ai_entities, duplicate_of,
		        duplicate_resolved, ai_generated, version, created_at, updated_at
		 FROM tasks
		 WHERE id = $1 AND user_id = $2 AND deleted_at IS NULL`,
		taskID, userID,
	).Scan(
		&task.ID, &task.UserID, &task.Title, &task.Description,
		&task.AICleanedTitle, &task.AICleanedDescription,
		&task.Status, &task.Priority, &dueAt, &task.HasDueTime, &completedAt, &tagsJSON,
		&task.ParentID, &task.Depth, &task.SortOrder, &task.Complexity, &entitiesJSON,
		&duplicateOfJSON, &task.DuplicateResolved, &task.AIGenerated, &task.Version,
		&task.CreatedAt, &task.UpdatedAt,
	)

	if err != nil {
		return nil, err
	}

	task.DueAt = dueAt
	task.CompletedAt = completedAt

	// Parse JSON fields
	if len(tagsJSON) > 0 {
		json.Unmarshal(tagsJSON, &task.Tags)
	}
	if len(entitiesJSON) > 0 {
		json.Unmarshal(entitiesJSON, &task.Entities)
	}
	if len(duplicateOfJSON) > 0 {
		json.Unmarshal(duplicateOfJSON, &task.DuplicateOf)
	}

	return &task, nil
}

// AIPreferences maps feature names to their settings (auto, ask, off)
type AIPreferences map[string]string

// determineFeatures determines which AI features to run based on tier, task state, and user preferences
func (p *AIProcessor) determineFeatures(tier UserTier, task *models.Task, prefs AIPreferences) []AIFeatureType {
	features := []AIFeatureType{}

	// Helper to check if feature is set to "auto"
	isAuto := func(key string) bool {
		val, ok := prefs[key]
		return !ok || val == "auto" // Default to auto if not set
	}

	// Title cleaning - only if preference is "auto" and AI cleaned title is nil
	if isAuto("clean_title") && task.AICleanedTitle == nil {
		features = append(features, AIFeatureCleanTitle)
	}

	// Description cleaning - only if preference is "auto"
	if isAuto("clean_description") && task.Description != nil && *task.Description != "" && task.AICleanedDescription == nil {
		features = append(features, AIFeatureCleanDescription)
	}

	// Due date extraction - only if preference is "auto"
	if isAuto("smart_due_date") && task.DueAt == nil {
		features = append(features, AIFeatureDueDate)
	}

	// Complexity - only if preference is "auto"
	if isAuto("complexity") && task.Complexity == 0 {
		features = append(features, AIFeatureComplexity)
	}

	// Tier-based features
	if tier == TierLight || tier == TierPremium {
		// Entity extraction - only if preference is "auto"
		if isAuto("entity_extraction") && len(task.Entities) == 0 {
			features = append(features, AIFeatureEntityExtraction)
		}
	}

	return features
}

// convertToQueueResult converts AIProcessResult to AIQueueResult
func (p *AIProcessor) convertToQueueResult(result *AIProcessResult, features []AIFeatureType) *AIQueueResult {
	queueResult := &AIQueueResult{
		ProcessedFeatures: features,
	}

	if result.CleanedTitle != nil {
		queueResult.CleanedTitle = result.CleanedTitle
	}
	if result.CleanedDesc != nil {
		queueResult.CleanedDesc = result.CleanedDesc
	}
	if len(result.Entities) > 0 {
		queueResult.Entities = result.Entities
	}
	if result.Complexity != nil {
		queueResult.Complexity = result.Complexity
	}
	if result.DueAt != nil {
		queueResult.DueAt = result.DueAt
		queueResult.HasDueTime = result.HasDueTime
	}
	if len(result.Steps) > 0 {
		queueResult.Subtasks = result.Steps
	}

	return queueResult
}

// writeResultsWithConflictCheck checks for conflicts and writes AI results
func (p *AIProcessor) writeResultsWithConflictCheck(ctx context.Context, taskID, userID uuid.UUID,
	snapshot TaskSnapshot, results *AIQueueResult) {

	// Get current state from DB
	current, err := p.getTask(ctx, taskID, userID)
	if err != nil || current == nil {
		return
	}

	// Check what changed since snapshot
	titleChanged := current.Title != snapshot.Title ||
		(current.AICleanedTitle != nil && snapshot.AICleanedTitle == nil)

	descChanged := false
	if current.Description != nil && snapshot.Description != nil {
		descChanged = *current.Description != *snapshot.Description
	} else if current.Description != snapshot.Description {
		descChanged = true
	}
	// Also check if AI cleaned description was manually set
	descChanged = descChanged || (current.AICleanedDescription != nil && snapshot.AICleanedDescription == nil)

	contentChanged := titleChanged || descChanged

	// Drop irrelevant results based on conflicts
	if titleChanged {
		results.CleanedTitle = nil
		// Remove from processed features
		results.ProcessedFeatures = removeFeature(results.ProcessedFeatures, AIFeatureCleanTitle)
	}
	if descChanged {
		results.CleanedDesc = nil
		results.ProcessedFeatures = removeFeature(results.ProcessedFeatures, AIFeatureCleanDescription)
	}

	// If content changed, entity extraction and other content-dependent features should restart
	if contentChanged {
		results.Entities = nil
		results.Complexity = nil
		results.ProcessedFeatures = removeFeature(results.ProcessedFeatures, AIFeatureEntityExtraction)
		results.ProcessedFeatures = removeFeature(results.ProcessedFeatures, AIFeatureComplexity)

		// Re-run AI processing with new content (recursive call with new snapshot)
		// Only if there are features that need re-running (use empty prefs to check task state only)
		featuresNeeded := p.determineFeatures(TierPremium, current, AIPreferences{})
		if len(featuresNeeded) > 0 {
			fmt.Printf("[AI Queue] Content changed during processing for task %s, restarting\n", taskID)
			go p.ProcessTaskAI(ctx, userID, taskID)
		}
	}

	// Check if there are any results to write
	if !hasResults(results) {
		return
	}

	// Write remaining results to DB
	if err := p.applyAIResults(ctx, taskID, userID, results); err != nil {
		fmt.Printf("[AI Queue] Failed to apply AI results for task %s: %v\n", taskID, err)
		return
	}

	// Publish WebSocket event via Redis
	p.publishTaskUpdate(ctx, userID, taskID, results)
}

// removeFeature removes a feature from the list
func removeFeature(features []AIFeatureType, toRemove AIFeatureType) []AIFeatureType {
	result := make([]AIFeatureType, 0, len(features))
	for _, f := range features {
		if f != toRemove {
			result = append(result, f)
		}
	}
	return result
}

// hasResults checks if there are any results to write
func hasResults(results *AIQueueResult) bool {
	return results.CleanedTitle != nil ||
		results.CleanedDesc != nil ||
		len(results.Entities) > 0 ||
		results.Complexity != nil ||
		results.DueAt != nil
}

// applyAIResults writes AI results to the database
func (p *AIProcessor) applyAIResults(ctx context.Context, taskID, userID uuid.UUID, results *AIQueueResult) error {
	// Build dynamic update query
	updates := []string{}
	args := []interface{}{}
	argNum := 1

	if results.CleanedTitle != nil {
		updates = append(updates, fmt.Sprintf("ai_cleaned_title = $%d", argNum))
		args = append(args, *results.CleanedTitle)
		argNum++
	}

	if results.CleanedDesc != nil {
		updates = append(updates, fmt.Sprintf("ai_cleaned_description = $%d", argNum))
		args = append(args, *results.CleanedDesc)
		argNum++
	}

	if results.DueAt != nil {
		updates = append(updates, fmt.Sprintf("due_at = $%d", argNum))
		args = append(args, *results.DueAt)
		argNum++
		updates = append(updates, fmt.Sprintf("has_due_time = $%d", argNum))
		args = append(args, results.HasDueTime)
		argNum++
		updates = append(updates, "ai_extracted_due = true")
	}

	if results.Complexity != nil {
		updates = append(updates, fmt.Sprintf("complexity = $%d", argNum))
		args = append(args, *results.Complexity)
		argNum++
	}

	if len(results.Entities) > 0 {
		entitiesJSON, _ := json.Marshal(results.Entities)
		updates = append(updates, fmt.Sprintf("ai_entities = $%d", argNum))
		args = append(args, entitiesJSON)
		argNum++
	}

	if len(updates) == 0 {
		return nil
	}

	// Add timestamp and version update
	updates = append(updates, fmt.Sprintf("updated_at = $%d", argNum))
	args = append(args, time.Now())
	argNum++

	updates = append(updates, "version = version + 1")

	// Add WHERE clause args
	args = append(args, taskID, userID)

	query := fmt.Sprintf(
		"UPDATE tasks SET %s WHERE id = $%d AND user_id = $%d",
		joinStrings(updates, ", "),
		argNum,
		argNum+1,
	)

	_, err := p.db.Exec(ctx, query, args...)
	return err
}

// joinStrings joins strings with a separator (simple helper to avoid importing strings)
func joinStrings(strs []string, sep string) string {
	if len(strs) == 0 {
		return ""
	}
	result := strs[0]
	for i := 1; i < len(strs); i++ {
		result += sep + strs[i]
	}
	return result
}

// publishTaskUpdate publishes a task update event via Redis Pub/Sub
func (p *AIProcessor) publishTaskUpdate(ctx context.Context, userID, taskID uuid.UUID, results *AIQueueResult) {
	if p.redis == nil {
		return
	}

	// Build list of completed features
	features := make([]string, 0, len(results.ProcessedFeatures))
	for _, f := range results.ProcessedFeatures {
		features = append(features, string(f))
	}

	// Create payload
	payload := ws.TaskAICompletePayload{
		TaskID:            taskID.String(),
		UserID:            userID.String(),
		Features:          features,
		AICleanedTitle:    results.CleanedTitle,
		AICleanedDesc:     results.CleanedDesc,
		EntitiesExtracted: len(results.Entities),
		Complexity:        results.Complexity,
	}

	msg, err := ws.NewMessage(ws.MsgTaskAIComplete, payload)
	if err != nil {
		return
	}

	// Publish to Redis channel for this user
	channel := fmt.Sprintf("ws:user:%s", userID.String())
	data, _ := json.Marshal(msg)
	p.redis.Publish(ctx, channel, data)
}
