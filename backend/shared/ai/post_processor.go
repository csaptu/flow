package ai

import (
	"encoding/json"
	"regexp"
	"strings"
)

// PostProcessor validates and sanitizes AI output
type PostProcessor struct {
	blockedPatterns []regexp.Regexp
}

// NewPostProcessor creates a new post processor
func NewPostProcessor() *PostProcessor {
	pp := &PostProcessor{}
	pp.initBlockedPatterns()
	return pp
}

// initBlockedPatterns initializes regional compliance patterns
func (pp *PostProcessor) initBlockedPatterns() {
	// Universal restrictions (very specific harmful content markers)
	universalPatterns := []string{
		`(?i)\b(how\s+to\s+make\s+a\s+bomb)\b`,
		`(?i)\b(suicide\s+method|ways\s+to\s+kill\s+yourself)\b`,
		`(?i)\b(child\s+porn|cp\s+links)\b`,
	}

	// Regional patterns are handled differently - we don't block content
	// but rather add a compliance note when certain topics are detected

	pp.blockedPatterns = make([]regexp.Regexp, 0, len(universalPatterns))
	for _, pattern := range universalPatterns {
		if re, err := regexp.Compile(pattern); err == nil {
			pp.blockedPatterns = append(pp.blockedPatterns, *re)
		}
	}
}

// ProcessResult represents the result of post-processing
type ProcessResult struct {
	Content    string   `json:"content"`
	IsBlocked  bool     `json:"is_blocked"`
	BlockedBy  string   `json:"blocked_by,omitempty"`
	Warnings   []string `json:"warnings,omitempty"`
	WasSanitized bool   `json:"was_sanitized"`
}

// Process validates and sanitizes AI output
func (pp *PostProcessor) Process(content string) *ProcessResult {
	result := &ProcessResult{
		Content:  content,
		Warnings: make([]string, 0),
	}

	// 1. Check for blocked patterns
	for _, pattern := range pp.blockedPatterns {
		if pattern.MatchString(content) {
			result.IsBlocked = true
			result.BlockedBy = "content_policy"
			result.Content = ""
			return result
		}
	}

	// 2. Sanitize HTML/scripts
	sanitized := pp.sanitizeHTML(content)
	if sanitized != content {
		result.WasSanitized = true
		content = sanitized
	}

	result.Content = content
	return result
}

// sanitizeHTML removes potentially dangerous HTML/script content
func (pp *PostProcessor) sanitizeHTML(content string) string {
	// Remove script tags
	scriptRe := regexp.MustCompile(`(?i)<script[^>]*>[\s\S]*?</script>`)
	content = scriptRe.ReplaceAllString(content, "")

	// Remove onclick and other event handlers
	eventRe := regexp.MustCompile(`(?i)\s+on\w+\s*=\s*["'][^"']*["']`)
	content = eventRe.ReplaceAllString(content, "")

	// Remove javascript: urls
	jsUrlRe := regexp.MustCompile(`(?i)javascript:\s*[^"'\s]+`)
	content = jsUrlRe.ReplaceAllString(content, "")

	// Remove iframes
	iframeRe := regexp.MustCompile(`(?i)<iframe[^>]*>[\s\S]*?</iframe>`)
	content = iframeRe.ReplaceAllString(content, "")

	// Remove style tags (can contain expressions)
	styleRe := regexp.MustCompile(`(?i)<style[^>]*>[\s\S]*?</style>`)
	content = styleRe.ReplaceAllString(content, "")

	return content
}

// ExtractJSON extracts JSON from potentially markdown-wrapped content
func (pp *PostProcessor) ExtractJSON(content string) (string, error) {
	content = strings.TrimSpace(content)

	// Try to extract from markdown code blocks
	if strings.HasPrefix(content, "```") {
		re := regexp.MustCompile("```(?:json)?\\s*([\\s\\S]*?)\\s*```")
		matches := re.FindStringSubmatch(content)
		if len(matches) > 1 {
			content = strings.TrimSpace(matches[1])
		}
	}

	// Validate it's valid JSON
	var js json.RawMessage
	if err := json.Unmarshal([]byte(content), &js); err != nil {
		// Try to find JSON object in the content
		startIdx := strings.Index(content, "{")
		endIdx := strings.LastIndex(content, "}")
		if startIdx >= 0 && endIdx > startIdx {
			extracted := content[startIdx : endIdx+1]
			if err := json.Unmarshal([]byte(extracted), &js); err == nil {
				return extracted, nil
			}
		}
		return content, err
	}

	return content, nil
}

// ValidateJSONSchema validates JSON against expected fields
func (pp *PostProcessor) ValidateJSONSchema(content string, requiredFields []string) (bool, []string) {
	var data map[string]interface{}
	if err := json.Unmarshal([]byte(content), &data); err != nil {
		return false, []string{"invalid JSON format"}
	}

	var missing []string
	for _, field := range requiredFields {
		if _, ok := data[field]; !ok {
			missing = append(missing, field)
		}
	}

	return len(missing) == 0, missing
}

// ProcessAndExtractJSON combines processing and JSON extraction
func (pp *PostProcessor) ProcessAndExtractJSON(content string) (*ProcessResult, string, error) {
	// First process for safety
	result := pp.Process(content)
	if result.IsBlocked {
		return result, "", nil
	}

	// Then extract JSON
	jsonContent, err := pp.ExtractJSON(result.Content)
	if err != nil {
		return result, result.Content, err
	}

	return result, jsonContent, nil
}

// TruncateResponse truncates response to max length with indicator
func (pp *PostProcessor) TruncateResponse(content string, maxLength int) string {
	if len(content) <= maxLength {
		return content
	}
	return content[:maxLength-3] + "..."
}

// CleanWhitespace normalizes whitespace in content
func (pp *PostProcessor) CleanWhitespace(content string) string {
	// Replace multiple spaces with single space
	spaceRe := regexp.MustCompile(`[ \t]+`)
	content = spaceRe.ReplaceAllString(content, " ")

	// Replace multiple newlines with double newline
	nlRe := regexp.MustCompile(`\n{3,}`)
	content = nlRe.ReplaceAllString(content, "\n\n")

	return strings.TrimSpace(content)
}
