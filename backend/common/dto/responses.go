package dto

import "time"

// APIResponse is the standard API response wrapper
type APIResponse struct {
	Success bool        `json:"success"`
	Data    interface{} `json:"data,omitempty"`
	Error   *APIError   `json:"error,omitempty"`
	Meta    *APIMeta    `json:"meta,omitempty"`
}

// APIError represents an error in the API response
type APIError struct {
	Code    string                 `json:"code"`
	Message string                 `json:"message"`
	Details map[string]interface{} `json:"details,omitempty"`
}

// APIMeta contains metadata about the response
type APIMeta struct {
	Page       int   `json:"page,omitempty"`
	PageSize   int   `json:"page_size,omitempty"`
	TotalCount int64 `json:"total_count,omitempty"`
	TotalPages int   `json:"total_pages,omitempty"`
}

// PaginationParams represents pagination query parameters
type PaginationParams struct {
	Page     int `json:"page" query:"page"`
	PageSize int `json:"page_size" query:"page_size"`
}

// DefaultPagination returns default pagination values
func DefaultPagination() PaginationParams {
	return PaginationParams{
		Page:     1,
		PageSize: 20,
	}
}

// Validate validates and normalizes pagination parameters
func (p *PaginationParams) Validate() {
	if p.Page < 1 {
		p.Page = 1
	}
	if p.PageSize < 1 {
		p.PageSize = 20
	}
	if p.PageSize > 100 {
		p.PageSize = 100
	}
}

// Offset returns the offset for database queries
func (p *PaginationParams) Offset() int {
	return (p.Page - 1) * p.PageSize
}

// HealthResponse represents the health check response
type HealthResponse struct {
	Status   string            `json:"status"`
	Version  string            `json:"version"`
	Services map[string]string `json:"services"`
}

// TokenPair represents JWT access and refresh tokens
type TokenPair struct {
	AccessToken  string    `json:"access_token"`
	RefreshToken string    `json:"refresh_token"`
	ExpiresAt    time.Time `json:"expires_at"`
	TokenType    string    `json:"token_type"`
}

// UserResponse represents a user in API responses
type UserResponse struct {
	ID            string  `json:"id"`
	Email         string  `json:"email"`
	EmailVerified bool    `json:"email_verified"`
	Name          string  `json:"name"`
	AvatarURL     *string `json:"avatar_url,omitempty"`
	CreatedAt     string  `json:"created_at"`
	UpdatedAt     string  `json:"updated_at"`
}

// SyncRequest represents a sync request from the client
type SyncRequest struct {
	LastSyncedAt time.Time       `json:"last_synced_at"`
	DeviceID     string          `json:"device_id"`
	Changes      []SyncOperation `json:"changes"`
}

// SyncOperation represents a single sync operation
type SyncOperation struct {
	Operation       string                 `json:"operation"` // create, update, delete
	TableName       string                 `json:"table_name"`
	RecordID        string                 `json:"record_id"`
	Data            map[string]interface{} `json:"data"`
	ClientTimestamp time.Time              `json:"client_timestamp"`
	Version         int                    `json:"version"`
}

// SyncResponse represents the sync response to the client
type SyncResponse struct {
	ServerTimestamp time.Time       `json:"server_timestamp"`
	Changes         []SyncOperation `json:"changes"`
	Conflicts       []SyncConflict  `json:"conflicts,omitempty"`
}

// SyncConflict represents a sync conflict that needs resolution
type SyncConflict struct {
	RecordID     string                 `json:"record_id"`
	ClientData   map[string]interface{} `json:"client_data"`
	ServerData   map[string]interface{} `json:"server_data"`
	Resolution   string                 `json:"resolution"` // client_wins, server_wins, merged
	ResolvedData map[string]interface{} `json:"resolved_data,omitempty"`
}

// Success creates a successful API response
func Success(data interface{}) APIResponse {
	return APIResponse{
		Success: true,
		Data:    data,
	}
}

// SuccessWithMeta creates a successful API response with metadata
func SuccessWithMeta(data interface{}, meta *APIMeta) APIResponse {
	return APIResponse{
		Success: true,
		Data:    data,
		Meta:    meta,
	}
}

// Error creates an error API response
func Error(code, message string) APIResponse {
	return APIResponse{
		Success: false,
		Error: &APIError{
			Code:    code,
			Message: message,
		},
	}
}

// ErrorWithDetails creates an error API response with details
func ErrorWithDetails(code, message string, details map[string]interface{}) APIResponse {
	return APIResponse{
		Success: false,
		Error: &APIError{
			Code:    code,
			Message: message,
			Details: details,
		},
	}
}
