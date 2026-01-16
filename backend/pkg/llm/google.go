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
	googleAPIURL       = "https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent?key=%s"
	defaultGoogleModel = "gemini-2.0-flash"
)

// GoogleClient is a client for the Google Generative AI API
type GoogleClient struct {
	apiKey     string
	httpClient *http.Client
}

// NewGoogleClient creates a new Google AI client
func NewGoogleClient(apiKey string) (*GoogleClient, error) {
	if apiKey == "" {
		return nil, fmt.Errorf("Google API key is required")
	}
	return &GoogleClient{
		apiKey:     apiKey,
		httpClient: &http.Client{},
	}, nil
}

// googleRequest is the request format for Google AI API
type googleRequest struct {
	Contents         []googleContent         `json:"contents"`
	SystemInstruction *googleContent         `json:"systemInstruction,omitempty"`
	GenerationConfig googleGenerationConfig `json:"generationConfig,omitempty"`
	Tools            []googleToolConfig     `json:"tools,omitempty"`
}

type googleContent struct {
	Parts []googlePart `json:"parts"`
	Role  string       `json:"role,omitempty"`
}

type googlePart struct {
	Text string `json:"text,omitempty"`
}

type googleGenerationConfig struct {
	Temperature     float64 `json:"temperature,omitempty"`
	MaxOutputTokens int     `json:"maxOutputTokens,omitempty"`
	TopP            float64 `json:"topP,omitempty"`
	TopK            int     `json:"topK,omitempty"`
}

type googleToolConfig struct {
	FunctionDeclarations []googleFunctionDecl `json:"functionDeclarations,omitempty"`
}

type googleFunctionDecl struct {
	Name        string          `json:"name"`
	Description string          `json:"description"`
	Parameters  json.RawMessage `json:"parameters"`
}

// googleResponse is the response format from Google AI API
type googleResponse struct {
	Candidates    []googleCandidate   `json:"candidates"`
	UsageMetadata googleUsageMetadata `json:"usageMetadata"`
}

type googleCandidate struct {
	Content      googleContent `json:"content"`
	FinishReason string        `json:"finishReason"`
}

type googleUsageMetadata struct {
	PromptTokenCount     int `json:"promptTokenCount"`
	CandidatesTokenCount int `json:"candidatesTokenCount"`
	TotalTokenCount      int `json:"totalTokenCount"`
}

// Complete implements the Client interface
func (c *GoogleClient) Complete(ctx context.Context, req CompletionRequest) (*CompletionResponse, error) {
	model := req.Model
	if model == "" {
		model = defaultGoogleModel
	}

	maxTokens := req.MaxTokens
	if maxTokens == 0 {
		maxTokens = 4096
	}

	// Convert messages
	var contents []googleContent
	var systemContent *googleContent

	for _, m := range req.Messages {
		if m.Role == "system" {
			systemContent = &googleContent{
				Parts: []googlePart{{Text: m.Content}},
			}
			continue
		}

		role := m.Role
		if role == "assistant" {
			role = "model"
		}

		contents = append(contents, googleContent{
			Role:  role,
			Parts: []googlePart{{Text: m.Content}},
		})
	}

	// Use explicit system message if provided
	if req.SystemMsg != "" {
		systemContent = &googleContent{
			Parts: []googlePart{{Text: req.SystemMsg}},
		}
	}

	// Convert tools
	var tools []googleToolConfig
	if len(req.Tools) > 0 {
		var funcs []googleFunctionDecl
		for _, t := range req.Tools {
			funcs = append(funcs, googleFunctionDecl{
				Name:        t.Name,
				Description: t.Description,
				Parameters:  t.Parameters,
			})
		}
		tools = append(tools, googleToolConfig{
			FunctionDeclarations: funcs,
		})
	}

	googleReq := googleRequest{
		Contents:          contents,
		SystemInstruction: systemContent,
		GenerationConfig: googleGenerationConfig{
			Temperature:     req.Temperature,
			MaxOutputTokens: maxTokens,
		},
		Tools: tools,
	}

	body, err := json.Marshal(googleReq)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal request: %w", err)
	}

	url := fmt.Sprintf(googleAPIURL, model, c.apiKey)
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

	var googleResp googleResponse
	if err := json.Unmarshal(respBody, &googleResp); err != nil {
		return nil, fmt.Errorf("failed to unmarshal response: %w", err)
	}

	// Convert response
	result := &CompletionResponse{
		Model: model,
		Usage: Usage{
			PromptTokens:     googleResp.UsageMetadata.PromptTokenCount,
			CompletionTokens: googleResp.UsageMetadata.CandidatesTokenCount,
			TotalTokens:      googleResp.UsageMetadata.TotalTokenCount,
		},
	}

	if len(googleResp.Candidates) > 0 && len(googleResp.Candidates[0].Content.Parts) > 0 {
		result.Content = googleResp.Candidates[0].Content.Parts[0].Text
	}

	return result, nil
}

// Stream implements streaming for Google AI
func (c *GoogleClient) Stream(ctx context.Context, req CompletionRequest) (<-chan StreamChunk, error) {
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
