package models

import (
	"encoding/json"
	"time"

	"github.com/google/uuid"
)

// User represents a user in the system
type User struct {
	ID            uuid.UUID `json:"id" db:"id"`
	Email         string    `json:"email" db:"email"`
	EmailVerified bool      `json:"email_verified" db:"email_verified"`
	PasswordHash  *string   `json:"-" db:"password_hash"` // Never expose in JSON
	Name          string    `json:"name" db:"name"`
	AvatarURL     *string   `json:"avatar_url,omitempty" db:"avatar_url"`

	// OAuth identifiers
	GoogleID    *string `json:"google_id,omitempty" db:"google_id"`
	AppleID     *string `json:"apple_id,omitempty" db:"apple_id"`
	MicrosoftID *string `json:"microsoft_id,omitempty" db:"microsoft_id"`

	// Settings stored as JSONB
	Settings json.RawMessage `json:"settings,omitempty" db:"settings"`

	// AI personalization
	AIProfile json.RawMessage `json:"ai_profile,omitempty" db:"ai_profile"`

	// Timestamps
	CreatedAt   time.Time  `json:"created_at" db:"created_at"`
	UpdatedAt   time.Time  `json:"updated_at" db:"updated_at"`
	LastLoginAt *time.Time `json:"last_login_at,omitempty" db:"last_login_at"`
	DeletedAt   *time.Time `json:"deleted_at,omitempty" db:"deleted_at"`
}

// UserSettings represents user preferences
type UserSettings struct {
	Theme         string `json:"theme,omitempty"`          // "light", "dark", "system"
	Notifications bool   `json:"notifications,omitempty"`  // Push notifications enabled
	Timezone      string `json:"timezone,omitempty"`       // e.g., "America/Los_Angeles"
	Language      string `json:"language,omitempty"`       // e.g., "en", "vi"
	AIPreferences AIPreferences `json:"ai_preferences,omitempty"`
}

// AIPreferences represents user's AI feature preferences
type AIPreferences struct {
	CleanTitle         AISetting `json:"clean_title"`
	CleanDescription   AISetting `json:"clean_description"`
	Decompose          AISetting `json:"decompose"`
	ComplexityCheck    AISetting `json:"complexity_check"`
	EntityExtraction   AISetting `json:"entity_extraction"`
	SmartDueDates      AISetting `json:"smart_due_dates"`
	RecurringDetection AISetting `json:"recurring_detection"`
	AutoGroup          AISetting `json:"auto_group"`
	DraftEmail         AISetting `json:"draft_email"`
	DraftCalendar      AISetting `json:"draft_calendar"`
	SendEmail          AISetting `json:"send_email"`
	SendCalendar       AISetting `json:"send_calendar"`
	Reminder           AISetting `json:"reminder"`
}

// AISetting represents how an AI feature should behave
type AISetting string

const (
	AISettingAuto AISetting = "auto" // AI runs automatically
	AISettingAsk  AISetting = "ask"  // AI suggests, user approves
	AISettingOff  AISetting = "off"  // Feature disabled
)

// DefaultAIPreferences returns the default AI preferences for new users
// All features default to "ask" (Manual) - user must explicitly enable auto
func DefaultAIPreferences() AIPreferences {
	return AIPreferences{
		CleanTitle:         AISettingAsk,
		CleanDescription:   AISettingAsk,
		Decompose:          AISettingAsk,
		ComplexityCheck:    AISettingAsk,
		EntityExtraction:   AISettingAsk,
		SmartDueDates:      AISettingAsk,
		RecurringDetection: AISettingAsk,
		AutoGroup:          AISettingAsk,
		DraftEmail:         AISettingAsk,
		DraftCalendar:      AISettingAsk,
		SendEmail:          AISettingAsk,
		SendCalendar:       AISettingAsk,
		Reminder:           AISettingAsk,
	}
}

// AIUserProfile represents AI-inferred user characteristics
type AIUserProfile struct {
	Archetype string   `json:"archetype,omitempty"` // e.g., "executive", "creative"
	Style     string   `json:"style,omitempty"`     // e.g., "concise", "detailed"
	PeakHours []int    `json:"peak_hours,omitempty"` // Productive hours
	Topics    []string `json:"topics,omitempty"`     // Common task topics
}

// GetSettings parses and returns the user settings
func (u *User) GetSettings() (*UserSettings, error) {
	if u.Settings == nil || len(u.Settings) == 0 {
		return &UserSettings{}, nil
	}
	var settings UserSettings
	if err := json.Unmarshal(u.Settings, &settings); err != nil {
		return nil, err
	}
	return &settings, nil
}

// SetSettings marshals and sets the user settings
func (u *User) SetSettings(settings *UserSettings) error {
	data, err := json.Marshal(settings)
	if err != nil {
		return err
	}
	u.Settings = data
	return nil
}

// GetAIProfile parses and returns the AI profile
func (u *User) GetAIProfile() (*AIUserProfile, error) {
	if u.AIProfile == nil || len(u.AIProfile) == 0 {
		return &AIUserProfile{}, nil
	}
	var profile AIUserProfile
	if err := json.Unmarshal(u.AIProfile, &profile); err != nil {
		return nil, err
	}
	return &profile, nil
}

// HasOAuthProvider checks if user has any OAuth provider linked
func (u *User) HasOAuthProvider() bool {
	return u.GoogleID != nil || u.AppleID != nil || u.MicrosoftID != nil
}

// CanPasswordLogin checks if user can login with password
func (u *User) CanPasswordLogin() bool {
	return u.PasswordHash != nil && *u.PasswordHash != ""
}
