CREATE INDEX idx_password_reset_tokens_user
    ON password_reset_tokens(user_id);

CREATE INDEX idx_password_reset_tokens_expiration
    ON password_reset_tokens(expires_at);

CREATE INDEX idx_password_reset_tokens_user_used
    ON password_reset_tokens(user_id, used);

CREATE UNIQUE INDEX uq_password_reset_tokens_unused_user
    ON password_reset_tokens(user_id)
    WHERE used = FALSE;
