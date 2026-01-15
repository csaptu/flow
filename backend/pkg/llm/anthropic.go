package llm

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
)

const (
	anthropicAPIURL = "https://api.anthropic.com/v1/messages"
	anthropicVersion = "2023-06-01"
	defaultAnthropicModel = "claude-sonnet-4-20250514"
)

// AnthropicClient is a client for the Anthropic API
type AnthropicClient struct {
	apiKey     string
	httpClient *http.Client
}

// NewAnthropicClient creates a new Anthropic client
func NewAnthropicClient(apiKey string) (*AnthropicClient, error) {
	if apiKey == "" {
		return nil, fmt.Errorf("Anthropic API key is required")
	}
	return &AnthropicClient{
		apiKey:     apiKey,
		httpClient: &http.Client{},
	}, nil
}

// anthropicRequest is the request format for Anthropic API
type anthropicRequest struct {
	Model       string            `json:"model"`
	MaxTokens   int               `json:"max_tokens"`
	Messages    []anthropicMsg    `json:"messages"`
	System      string            `json:"system,omitempty"`
	Temperature float64           `json:"temperature,omitempty"`
	Tools       []anthropicTool   `json:"tools,omitempty"`
}

type anthropicMsg struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

type anthropicTool struct {
	Name        string          `json:"name"`
	Description string          `json:"description"`
	InputSchema json.RawMessage `json:"input_schema"`
}

// anthropicResponse is the response format from Anthropic API
type anthropicResponse struct {
	ID           string              `json:"id"`
	Type         string              `json:"type"`
	Role         string              `json:"role"`
	Content      []anthropicContent  `json:"content"`
	Model        string              `json:"model"`
	StopReason   string              `json:"stop_reason"`
	Usage        anthropicUsage      `json:"usage"`
}

type anthropicContent struct {
	Type      string          `json:"type"`
	Text      string          `json:"text,omitempty"`
	ID        string          `json:"id,omitempty"`
	Name      string          `json:"name,omitempty"`
	Input     json.RawMessage `json:"input,omitempty"`
}

type anthropicUsage struct {
	InputTokens  int `json:"input_tokens"`
	OutputTokens int `json:"output_tokens"`
}

// Complete implements the Client interface
func (c *AnthropicClient) Complete(ctx context.Context, req CompletionRequest) (*CompletionResponse, error) {
	model := req.Model
	if model == "" {
		model = defaultAnthropicModel
	}

	maxTokens := req.MaxTokens
	if maxTokens == 0 {
		maxTokens = 4096
	}

	// Convert messages
	msgs := make([]anthropicMsg, 0, len(req.Messages))
	var systemMsg string
	for _, m := range req.Messages {
		if m.Role == "system" {
			systemMsg = m.Content
			continue
		}
		msgs = append(msgs, anthropicMsg{
			Role:    m.Role,
			Content: m.Content,
		})
	}

	// Use explicit system message if provided
	if req.SystemMsg != "" {
		systemMsg = req.SystemMsg
	}

	// Convert tools
	var tools []anthropicTool
	for _, t := range req.Tools {
		tools = append(tools, anthropicTool{
			Name:        t.Name,
			Description: t.Description,
			InputSchema: t.Parameters,
		})
	}

	anthropicReq := anthropicRequest{
		Model:       model,
		MaxTokens:   maxTokens,
		Messages:    msgs,
		System:      systemMsg,
		Temperature: req.Temperature,
		Tools:       tools,
	}

	body, err := json.Marshal(anthropicReq)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal request: %w", err)
	}

	httpReq, err := http.NewRequestWithContext(ctx, "POST", anthropicAPIURL, bytes.NewReader(body))
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	httpReq.Header.Set("Content-Type", "application/json")
	httpReq.Header.Set("x-api-key", c.apiKey)
	httpReq.Header.Set("anthropic-version", anthropicVersion)

	resp, err := c.httpClient.Do(httpReq)
	if err != nil {
		return nil, fmt.Errorf("request failed: %w", err)
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read response: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("API error (status %d): %s", resp.StatusCode, string(respBody))
	}

	var anthropicResp anthropicResponse
	if err := json.Unmarshal(respBody, &anthropicResp); err != nil {
		return nil, fmt.Errorf("failed to unmarshal response: %w", err)
	}

	// Convert response
	result := &CompletionResponse{
		Model: anthropicResp.Model,
		Usage: Usage{
			PromptTokens:     anthropicResp.Usage.InputTokens,
			CompletionTokens: anthropicResp.Usage.OutputTokens,
			TotalTokens:      anthropicResp.Usage.InputTokens + anthropicResp.Usage.OutputTokens,
		},
	}

	for _, content := range anthropicResp.Content {
		switch content.Type {
		case "text":
			result.Content = content.Text
		case "tool_use":
			result.ToolCalls = append(result.ToolCalls, ToolCall{
				ID:         content.ID,
				Name:       content.Name,
				Parameters: content.Input,
			})
		}
	}

	return result, nil
}

// Stream implements streaming for Anthropic
func (c *AnthropicClient) Stream(ctx context.Context, req CompletionRequest) (<-chan StreamChunk, error) {
	// For now, implement as a simple wrapper around Complete
	// Full streaming implementation would use SSE
	ch := make(chan StreamChunk)

	go func() {
		defer close(ch)

		resp, err := c.Complete(ctx, req)
		if err != nil {
			ch <- StreamChunk{Done: true}
			return
		}

		ch <- StreamChunk{
			Content: resp.Content,
			Done:    true,
		}
	}()

	return ch, nil
}
