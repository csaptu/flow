package oauth

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"
)

// GoogleTokenInfo represents the response from Google's tokeninfo endpoint
type GoogleTokenInfo struct {
	Iss           string `json:"iss"`            // Issuer
	Azp           string `json:"azp"`            // Authorized party
	Aud           string `json:"aud"`            // Audience (client ID)
	Sub           string `json:"sub"`            // Subject (Google user ID)
	Email         string `json:"email"`          // User email
	EmailVerified string `json:"email_verified"` // "true" or "false"
	AtHash        string `json:"at_hash"`        // Access token hash
	Name          string `json:"name"`           // User's full name
	Picture       string `json:"picture"`        // Profile picture URL
	GivenName     string `json:"given_name"`     // First name
	FamilyName    string `json:"family_name"`    // Last name
	Locale        string `json:"locale"`         // User's locale
	Iat           string `json:"iat"`            // Issued at
	Exp           string `json:"exp"`            // Expiration time
}

// GoogleUser represents verified Google user information
type GoogleUser struct {
	GoogleID      string
	Email         string
	EmailVerified bool
	Name          string
	GivenName     string
	FamilyName    string
	Picture       string
}

// VerifyGoogleIDToken verifies a Google ID token and returns user info
func VerifyGoogleIDToken(ctx context.Context, idToken string, clientID string) (*GoogleUser, error) {
	// Use Google's tokeninfo endpoint for verification
	url := fmt.Sprintf("https://oauth2.googleapis.com/tokeninfo?id_token=%s", idToken)

	req, err := http.NewRequestWithContext(ctx, "GET", url, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("failed to verify token: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("token verification failed: %s", string(body))
	}

	var tokenInfo GoogleTokenInfo
	if err := json.NewDecoder(resp.Body).Decode(&tokenInfo); err != nil {
		return nil, fmt.Errorf("failed to decode response: %w", err)
	}

	// Verify the audience matches our client ID
	if tokenInfo.Aud != clientID {
		return nil, fmt.Errorf("token audience mismatch: expected %s, got %s", clientID, tokenInfo.Aud)
	}

	// Verify the issuer
	if tokenInfo.Iss != "https://accounts.google.com" && tokenInfo.Iss != "accounts.google.com" {
		return nil, fmt.Errorf("invalid token issuer: %s", tokenInfo.Iss)
	}

	return &GoogleUser{
		GoogleID:      tokenInfo.Sub,
		Email:         tokenInfo.Email,
		EmailVerified: tokenInfo.EmailVerified == "true",
		Name:          tokenInfo.Name,
		GivenName:     tokenInfo.GivenName,
		FamilyName:    tokenInfo.FamilyName,
		Picture:       tokenInfo.Picture,
	}, nil
}

// GoogleUserInfo represents the response from Google's userinfo endpoint
type GoogleUserInfo struct {
	Sub           string `json:"sub"`
	Email         string `json:"email"`
	EmailVerified bool   `json:"email_verified"`
	Name          string `json:"name"`
	GivenName     string `json:"given_name"`
	FamilyName    string `json:"family_name"`
	Picture       string `json:"picture"`
}

// VerifyGoogleAccessToken verifies a Google access token using the userinfo endpoint
func VerifyGoogleAccessToken(ctx context.Context, accessToken string) (*GoogleUser, error) {
	url := "https://www.googleapis.com/oauth2/v3/userinfo"

	req, err := http.NewRequestWithContext(ctx, "GET", url, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}
	req.Header.Set("Authorization", "Bearer "+accessToken)

	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("failed to verify token: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("token verification failed: %s", string(body))
	}

	var userInfo GoogleUserInfo
	if err := json.NewDecoder(resp.Body).Decode(&userInfo); err != nil {
		return nil, fmt.Errorf("failed to decode response: %w", err)
	}

	return &GoogleUser{
		GoogleID:      userInfo.Sub,
		Email:         userInfo.Email,
		EmailVerified: userInfo.EmailVerified,
		Name:          userInfo.Name,
		GivenName:     userInfo.GivenName,
		FamilyName:    userInfo.FamilyName,
		Picture:       userInfo.Picture,
	}, nil
}
