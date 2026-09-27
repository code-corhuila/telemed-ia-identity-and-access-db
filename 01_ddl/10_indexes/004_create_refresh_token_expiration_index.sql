CREATE INDEX idx_refresh_tokens_expiration
    ON refresh_tokens(expires_at);