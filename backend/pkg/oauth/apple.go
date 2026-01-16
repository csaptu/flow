package oauth

import (
	"context"
	"crypto/rsa"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"math/big"
	"net/http"
	"strings"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

// AppleJWKSet represents Apple's public key set
type AppleJWKSet struct {
	Keys []AppleJWK `json:"keys"`
}

// AppleJWK represents a single Apple JSON Web Key
type AppleJWK struct {
	Kty string `json:"kty"` // Key type (RSA)
	Kid string `json:"kid"` // Key ID
	Use string `json:"use"` // Usage (sig for signature)
	Alg string `json:"alg"` // Algorithm (RS256)
	N   string `json:"n"`   // Modulus
	E   string `json:"e"`   // Exponent
}

// AppleClaims represents claims from Apple ID token
type AppleClaims struct {
	jwt.RegisteredClaims
	Email         string `json:"email"`
	EmailVerified any    `json:"email_verified"` // Can be bool or string
	IsPrivateEmail any   `json:"is_private_email"`
	AuthTime      int64  `json:"auth_time"`
	NonceSupported bool  `json:"nonce_supported"`
}

// AppleUser represents verified Apple user information
type AppleUser struct {
	AppleID       string
	Email         string
	EmailVerified bool
	IsPrivateEmail bool
}

var (
	appleKeysCache     *AppleJWKSet
	appleKeysCacheTime time.Time
	appleKeysCacheTTL  = 24 * time.Hour
)

// VerifyAppleIDToken verifies an Apple ID token and returns user info
func VerifyAppleIDToken(ctx context.Context, idToken string, clientID string) (*AppleUser, error) {
	// Get Apple's public keys
	keys, err := getApplePublicKeys(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to get Apple public keys: %w", err)
	}

	// Parse the token header to get the key ID
	parts := strings.Split(idToken, ".")
	if len(parts) != 3 {
		return nil, fmt.Errorf("invalid token format")
	}

	headerBytes, err := base64.RawURLEncoding.DecodeString(parts[0])
	if err != nil {
		return nil, fmt.Errorf("failed to decode token header: %w", err)
	}

	var header struct {
		Kid string `json:"kid"`
		Alg string `json:"alg"`
	}
	if err := json.Unmarshal(headerBytes, &header); err != nil {
		return nil, fmt.Errorf("failed to parse token header: %w", err)
	}

	// Find the matching key
	var publicKey *rsa.PublicKey
	for _, key := range keys.Keys {
		if key.Kid == header.Kid {
			publicKey, err = jwkToRSAPublicKey(&key)
			if err != nil {
				return nil, fmt.Errorf("failed to convert JWK to RSA key: %w", err)
			}
			break
		}
	}

	if publicKey == nil {
		return nil, fmt.Errorf("no matching key found for kid: %s", header.Kid)
	}

	// Parse and verify the token
	var claims AppleClaims
	token, err := jwt.ParseWithClaims(idToken, &claims, func(token *jwt.Token) (interface{}, error) {
		return publicKey, nil
	})
	if err != nil {
		return nil, fmt.Errorf("failed to verify token: %w", err)
	}

	if !token.Valid {
		return nil, fmt.Errorf("invalid token")
	}

	// Verify issuer
	if claims.Issuer != "https://appleid.apple.com" {
		return nil, fmt.Errorf("invalid token issuer: %s", claims.Issuer)
	}

	// Verify audience
	validAudience := false
	for _, aud := range claims.Audience {
		if aud == clientID {
			validAudience = true
			break
		}
	}
	if !validAudience {
		return nil, fmt.Errorf("token audience mismatch")
	}

	// Parse email_verified (can be bool or string)
	emailVerified := false
	switch v := claims.EmailVerified.(type) {
	case bool:
		emailVerified = v
	case string:
		emailVerified = v == "true"
	}

	// Parse is_private_email
	isPrivateEmail := false
	switch v := claims.IsPrivateEmail.(type) {
	case bool:
		isPrivateEmail = v
	case string:
		isPrivateEmail = v == "true"
	}

	return &AppleUser{
		AppleID:        claims.Subject,
		Email:          claims.Email,
		EmailVerified:  emailVerified,
		IsPrivateEmail: isPrivateEmail,
	}, nil
}

// getApplePublicKeys fetches Apple's public keys with caching
func getApplePublicKeys(ctx context.Context) (*AppleJWKSet, error) {
	// Check cache
	if appleKeysCache != nil && time.Since(appleKeysCacheTime) < appleKeysCacheTTL {
		return appleKeysCache, nil
	}

	req, err := http.NewRequestWithContext(ctx, "GET", "https://appleid.apple.com/auth/keys", nil)
	if err != nil {
		return nil, err
	}

	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("failed to fetch Apple keys: %s", string(body))
	}

	var keys AppleJWKSet
	if err := json.NewDecoder(resp.Body).Decode(&keys); err != nil {
		return nil, err
	}

	// Update cache
	appleKeysCache = &keys
	appleKeysCacheTime = time.Now()

	return &keys, nil
}

// jwkToRSAPublicKey converts an Apple JWK to an RSA public key
func jwkToRSAPublicKey(jwk *AppleJWK) (*rsa.PublicKey, error) {
	// Decode the modulus
	nBytes, err := base64.RawURLEncoding.DecodeString(jwk.N)
	if err != nil {
		return nil, fmt.Errorf("failed to decode modulus: %w", err)
	}
	n := new(big.Int).SetBytes(nBytes)

	// Decode the exponent
	eBytes, err := base64.RawURLEncoding.DecodeString(jwk.E)
	if err != nil {
		return nil, fmt.Errorf("failed to decode exponent: %w", err)
	}
	var e int
	for _, b := range eBytes {
		e = e<<8 + int(b)
	}

	return &rsa.PublicKey{
		N: n,
		E: e,
	}, nil
}
