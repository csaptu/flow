package email

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"
)

const resendAPIURL = "https://api.resend.com/emails"

// Client is an email client using Resend
type Client struct {
	apiKey string
	from   string
	client *http.Client
}

// NewClient creates a new email client
func NewClient(apiKey, from string) *Client {
	return &Client{
		apiKey: apiKey,
		from:   from,
		client: &http.Client{Timeout: 10 * time.Second},
	}
}

// Email represents an email to send
type Email struct {
	To      []string `json:"to"`
	Subject string   `json:"subject"`
	HTML    string   `json:"html,omitempty"`
	Text    string   `json:"text,omitempty"`
}

// resendRequest is the request body for Resend API
type resendRequest struct {
	From    string   `json:"from"`
	To      []string `json:"to"`
	Subject string   `json:"subject"`
	HTML    string   `json:"html,omitempty"`
	Text    string   `json:"text,omitempty"`
}

// resendResponse is the response from Resend API
type resendResponse struct {
	ID string `json:"id"`
}

// resendError is an error response from Resend API
type resendError struct {
	StatusCode int    `json:"statusCode"`
	Name       string `json:"name"`
	Message    string `json:"message"`
}

// Send sends an email
func (c *Client) Send(ctx context.Context, email Email) (string, error) {
	if c.apiKey == "" {
		return "", fmt.Errorf("email not configured: missing RESEND_API_KEY")
	}

	reqBody := resendRequest{
		From:    c.from,
		To:      email.To,
		Subject: email.Subject,
		HTML:    email.HTML,
		Text:    email.Text,
	}

	jsonBody, err := json.Marshal(reqBody)
	if err != nil {
		return "", fmt.Errorf("failed to marshal email request: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, "POST", resendAPIURL, bytes.NewBuffer(jsonBody))
	if err != nil {
		return "", fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("Authorization", "Bearer "+c.apiKey)
	req.Header.Set("Content-Type", "application/json")

	resp, err := c.client.Do(req)
	if err != nil {
		return "", fmt.Errorf("failed to send email: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", fmt.Errorf("failed to read response: %w", err)
	}

	if resp.StatusCode >= 400 {
		var errResp resendError
		if err := json.Unmarshal(body, &errResp); err == nil {
			return "", fmt.Errorf("resend error: %s - %s", errResp.Name, errResp.Message)
		}
		return "", fmt.Errorf("resend error: status %d - %s", resp.StatusCode, string(body))
	}

	var result resendResponse
	if err := json.Unmarshal(body, &result); err != nil {
		return "", fmt.Errorf("failed to parse response: %w", err)
	}

	return result.ID, nil
}

// SendPasswordReset sends a password reset email (legacy - with link)
func (c *Client) SendPasswordReset(ctx context.Context, toEmail, resetToken, resetURL string) error {
	return c.SendPasswordResetCode(ctx, toEmail, resetToken)
}

// SendPasswordResetCode sends a password reset email with 6-digit code
func (c *Client) SendPasswordResetCode(ctx context.Context, toEmail, code string) error {
	html := fmt.Sprintf(`
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; line-height: 1.6; color: #333; }
        .container { max-width: 600px; margin: 0 auto; padding: 20px; }
        .code-box { background: #f3f4f6; border-radius: 12px; padding: 24px; text-align: center; margin: 24px 0; }
        .code { font-size: 36px; font-weight: bold; letter-spacing: 8px; color: #1f2937; font-family: monospace; }
        .footer { margin-top: 30px; font-size: 12px; color: #666; }
    </style>
</head>
<body>
    <div class="container">
        <h2>Reset your password</h2>
        <p>We received a request to reset your Flow password. Enter this code in the app to continue:</p>
        <div class="code-box">
            <div class="code">%s</div>
        </div>
        <p>This code will expire in <strong>10 minutes</strong>.</p>
        <p>If you didn't request a password reset, you can safely ignore this email. Someone may have typed your email by mistake.</p>
        <div class="footer">
            <p>Flow<br>This is an automated message, please do not reply.</p>
        </div>
    </div>
</body>
</html>`, code)

	text := fmt.Sprintf(`Reset your password

We received a request to reset your Flow password.

Your verification code is: %s

This code will expire in 10 minutes.

If you didn't request a password reset, you can safely ignore this email.

Flow`, code)

	_, err := c.Send(ctx, Email{
		To:      []string{toEmail},
		Subject: "Your Flow verification code: " + code,
		HTML:    html,
		Text:    text,
	})
	return err
}

// SendVerificationCode sends an email verification code for new registration
func (c *Client) SendVerificationCode(ctx context.Context, toEmail, code string) error {
	html := fmt.Sprintf(`
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; line-height: 1.6; color: #333; }
        .container { max-width: 600px; margin: 0 auto; padding: 20px; }
        .code-box { background: #f3f4f6; border-radius: 12px; padding: 24px; text-align: center; margin: 24px 0; }
        .code { font-size: 36px; font-weight: bold; letter-spacing: 8px; color: #1f2937; font-family: monospace; }
        .footer { margin-top: 30px; font-size: 12px; color: #666; }
    </style>
</head>
<body>
    <div class="container">
        <h2>Welcome to Flow!</h2>
        <p>Thanks for signing up. Please verify your email address by entering this code in the app:</p>
        <div class="code-box">
            <div class="code">%s</div>
        </div>
        <p>This code will expire in <strong>10 minutes</strong>.</p>
        <p>If you didn't create a Flow account, you can safely ignore this email.</p>
        <div class="footer">
            <p>Flow<br>This is an automated message, please do not reply.</p>
        </div>
    </div>
</body>
</html>`, code)

	text := fmt.Sprintf(`Welcome to Flow!

Thanks for signing up. Please verify your email address.

Your verification code is: %s

This code will expire in 10 minutes.

If you didn't create a Flow account, you can safely ignore this email.

Flow`, code)

	_, err := c.Send(ctx, Email{
		To:      []string{toEmail},
		Subject: "Verify your Flow account: " + code,
		HTML:    html,
		Text:    text,
	})
	return err
}
