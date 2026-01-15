package llm

import (
	"context"
	"encoding/json"
	"fmt"
)

// Provider represents an LLM provider
type Provider string

const (
	ProviderAnthropic Provider = "anthropic"
	ProviderGoogle    Provider = "google"
	ProviderOpenAI    Provider = "openai"
	ProviderOllama    Provider = "ollama"
)

// Message represents a chat message
type Message struct {
	Role    string `json:"role"`    // system, user, assistant
	Content string `json:"content"`
}

// Tool represents a function/tool that can be called by the LLM
type Tool struct {
	Name        string          `json:"name"`
	Description string          `json:"description"`
	Parameters  json.RawMessage `json:"parameters"` // JSON Schema
}

// ToolCall represents a tool invocation by the LLM
type ToolCall struct {
	ID         string          `json:"id"`
	Name       string          `json:"name"`
	Parameters json.RawMessage `json:"parameters"`
}

// CompletionRequest represents a request to the LLM
type CompletionRequest struct {
	Provider    Provider
	Model       string
	Messages    []Message
	MaxTokens   int
	Temperature float64
	Tools       []Tool
	SystemMsg   string // Optional system message
}

// CompletionResponse represents the LLM response
type CompletionResponse struct {
	Content   string     `json:"content"`
	ToolCalls []ToolCall `json:"tool_calls,omitempty"`
	Usage     Usage      `json:"usage"`
	Model     string     `json:"model"`
}

// Usage represents token usage information
type Usage struct {
	PromptTokens     int `json:"prompt_tokens"`
	CompletionTokens int `json:"completion_tokens"`
	TotalTokens      int `json:"total_tokens"`
}

// StreamChunk represents a streaming response chunk
type StreamChunk struct {
	Content  string `json:"content"`
	Done     bool   `json:"done"`
	ToolCall *ToolCall `json:"tool_call,omitempty"`
}

// Client is the interface for LLM clients
type Client interface {
	// Complete sends a completion request and returns the response
	Complete(ctx context.Context, req CompletionRequest) (*CompletionResponse, error)
	// Stream sends a completion request and returns a streaming channel
	Stream(ctx context.Context, req CompletionRequest) (<-chan StreamChunk, error)
}

// MultiClient manages multiple LLM providers
type MultiClient struct {
	providers map[Provider]Client
	fallbacks map[Provider][]Provider
	defaultProvider Provider
}

// NewMultiClient creates a new multi-provider client
func NewMultiClient(config Config) (*MultiClient, error) {
	mc := &MultiClient{
		providers: make(map[Provider]Client),
		fallbacks: make(map[Provider][]Provider),
		defaultProvider: config.DefaultProvider,
	}

	// Initialize Anthropic client if configured
	if config.AnthropicAPIKey != "" {
		client, err := NewAnthropicClient(config.AnthropicAPIKey)
		if err != nil {
			return nil, fmt.Errorf("failed to create Anthropic client: %w", err)
		}
		mc.providers[ProviderAnthropic] = client
	}

	// Initialize Google client if configured
	if config.GoogleAPIKey != "" {
		client, err := NewGoogleClient(config.GoogleAPIKey)
		if err != nil {
			return nil, fmt.Errorf("failed to create Google client: %w", err)
		}
		mc.providers[ProviderGoogle] = client
	}

	// Initialize OpenAI client if configured
	if config.OpenAIAPIKey != "" {
		client, err := NewOpenAIClient(config.OpenAIAPIKey)
		if err != nil {
			return nil, fmt.Errorf("failed to create OpenAI client: %w", err)
		}
		mc.providers[ProviderOpenAI] = client
	}

	// Initialize Ollama client (always available for local)
	if config.OllamaHost != "" {
		client, err := NewOllamaClient(config.OllamaHost, config.OllamaModel)
		if err != nil {
			// Don't fail if Ollama is not available
			fmt.Printf("Warning: Ollama client initialization failed: %v\n", err)
		} else {
			mc.providers[ProviderOllama] = client
		}
	}

	// Set up fallback chains
	mc.fallbacks[ProviderAnthropic] = []Provider{ProviderOpenAI, ProviderGoogle}
	mc.fallbacks[ProviderGoogle] = []Provider{ProviderAnthropic, ProviderOpenAI}
	mc.fallbacks[ProviderOpenAI] = []Provider{ProviderAnthropic, ProviderGoogle}
	mc.fallbacks[ProviderOllama] = []Provider{ProviderAnthropic, ProviderGoogle}

	return mc, nil
}

// Complete sends a completion request, using fallbacks if needed
func (mc *MultiClient) Complete(ctx context.Context, req CompletionRequest) (*CompletionResponse, error) {
	provider := req.Provider
	if provider == "" {
		provider = mc.defaultProvider
	}

	// Try primary provider
	if client, ok := mc.providers[provider]; ok {
		resp, err := client.Complete(ctx, req)
		if err == nil {
			return resp, nil
		}
		// Log error and try fallbacks
		fmt.Printf("Provider %s failed: %v, trying fallbacks\n", provider, err)
	}

	// Try fallback providers
	for _, fallback := range mc.fallbacks[provider] {
		if client, ok := mc.providers[fallback]; ok {
			req.Provider = fallback
			resp, err := client.Complete(ctx, req)
			if err == nil {
				return resp, nil
			}
			fmt.Printf("Fallback provider %s failed: %v\n", fallback, err)
		}
	}

	return nil, fmt.Errorf("all LLM providers failed")
}

// Stream sends a streaming completion request
func (mc *MultiClient) Stream(ctx context.Context, req CompletionRequest) (<-chan StreamChunk, error) {
	provider := req.Provider
	if provider == "" {
		provider = mc.defaultProvider
	}

	if client, ok := mc.providers[provider]; ok {
		return client.Stream(ctx, req)
	}

	return nil, fmt.Errorf("provider %s not available", provider)
}

// GetProvider returns the client for a specific provider
func (mc *MultiClient) GetProvider(provider Provider) (Client, bool) {
	client, ok := mc.providers[provider]
	return client, ok
}

// IsProviderAvailable checks if a provider is configured and available
func (mc *MultiClient) IsProviderAvailable(provider Provider) bool {
	_, ok := mc.providers[provider]
	return ok
}

// Config holds LLM client configuration
type Config struct {
	DefaultProvider Provider
	AnthropicAPIKey string
	GoogleAPIKey    string
	OpenAIAPIKey    string
	OllamaHost      string
	OllamaModel     string
}

// NewConfigFromEnv creates config from package config
func NewConfigFromEnv(cfg struct {
	DefaultProvider string
	AnthropicAPIKey string
	GoogleAPIKey    string
	OpenAIAPIKey    string
	OllamaHost      string
	OllamaModel     string
}) Config {
	return Config{
		DefaultProvider: Provider(cfg.DefaultProvider),
		AnthropicAPIKey: cfg.AnthropicAPIKey,
		GoogleAPIKey:    cfg.GoogleAPIKey,
		OpenAIAPIKey:    cfg.OpenAIAPIKey,
		OllamaHost:      cfg.OllamaHost,
		OllamaModel:     cfg.OllamaModel,
	}
}
