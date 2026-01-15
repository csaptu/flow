package llm

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
)

// OllamaClient is a client for the Ollama local LLM API
type OllamaClient struct {
	host       string
	model      string
	httpClient *http.Client
}

// NewOllamaClient creates a new Ollama client
func NewOllamaClient(host, model string) (*OllamaClient, error) {
	if host == "" {
		host = "http://localhost:11434"
	}
	if model == "" {
		model = "llama3.1:8b"
	}

	client := &OllamaClient{
		host:       host,
		model:      model,
		httpClient: &http.Client{},
	}

	// Test connection
	if err := client.ping(); err != nil {
		return nil, fmt.Errorf("failed to connect to Ollama: %w", err)
	}

	return client, nil
}

func (c *OllamaClient) ping() error {
	resp, err := c.httpClient.Get(c.host + "/api/tags")
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("Ollama returned status %d", resp.StatusCode)
	}
	return nil
}

// ollamaRequest is the request format for Ollama API
type ollamaRequest struct {
	Model    string          `json:"model"`
	Messages []ollamaMessage `json:"messages"`
	Stream   bool            `json:"stream"`
	Options  ollamaOptions   `json:"options,omitempty"`
}

type ollamaMessage struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

type ollamaOptions struct {
	Temperature float64 `json:"temperature,omitempty"`
	NumPredict  int     `json:"num_predict,omitempty"`
}

// ollamaResponse is the response format from Ollama API
type ollamaResponse struct {
	Model     string        `json:"model"`
	Message   ollamaMessage `json:"message"`
	Done      bool          `json:"done"`
	DoneReason string       `json:"done_reason,omitempty"`
	TotalDuration int64     `json:"total_duration"`
	EvalCount     int       `json:"eval_count"`
	PromptEvalCount int     `json:"prompt_eval_count"`
}

// Complete implements the Client interface
func (c *OllamaClient) Complete(ctx context.Context, req CompletionRequest) (*CompletionResponse, error) {
	model := req.Model
	if model == "" {
		model = c.model
	}

	maxTokens := req.MaxTokens
	if maxTokens == 0 {
		maxTokens = 4096
	}

	// Convert messages
	var msgs []ollamaMessage
	for _, m := range req.Messages {
		msgs = append(msgs, ollamaMessage{
			Role:    m.Role,
			Content: m.Content,
		})
	}

	// Add system message if provided
	if req.SystemMsg != "" {
		msgs = append([]ollamaMessage{{
			Role:    "system",
			Content: req.SystemMsg,
		}}, msgs...)
	}

	ollamaReq := ollamaRequest{
		Model:    model,
		Messages: msgs,
		Stream:   false,
		Options: ollamaOptions{
			Temperature: req.Temperature,
			NumPredict:  maxTokens,
		},
	}

	body, err := json.Marshal(ollamaReq)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal request: %w", err)
	}

	url := c.host + "/api/chat"
	httpReq, err := http.NewRequestWithContext(ctx, "POST", url, bytes.NewReader(body))
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	httpReq.Header.Set("Content-Type", "application/json")

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

	var ollamaResp ollamaResponse
	if err := json.Unmarshal(respBody, &ollamaResp); err != nil {
		return nil, fmt.Errorf("failed to unmarshal response: %w", err)
	}

	return &CompletionResponse{
		Content: ollamaResp.Message.Content,
		Model:   ollamaResp.Model,
		Usage: Usage{
			PromptTokens:     ollamaResp.PromptEvalCount,
			CompletionTokens: ollamaResp.EvalCount,
			TotalTokens:      ollamaResp.PromptEvalCount + ollamaResp.EvalCount,
		},
	}, nil
}

// Stream implements streaming for Ollama
func (c *OllamaClient) Stream(ctx context.Context, req CompletionRequest) (<-chan StreamChunk, error) {
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
