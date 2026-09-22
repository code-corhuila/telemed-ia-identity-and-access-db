-- ============================================================
-- Identity & Access
-- V5 - Create password reset tokens table
-- ============================================================

CREATE TABLE password_reset_tokens (
    id BIGSERIAL PRIMARY KEY,

    user_id BIGINT NOT NULL,

    token_hash VARCHAR(120) NOT NULL UNIQUE,

    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    expires_at TIMESTAMPTZ NOT NULL,

    used BOOLEAN NOT NULL DEFAULT FALSE,

    CONSTRAINT fk_password_reset_tokens_user
        FOREIGN KEY (user_id)
        REFERENCES users(id)
        ON DELETE RESTRICT
);

CREATE INDEX idx_password_reset_tokens_user
    ON password_reset_tokens(user_id);

CREATE INDEX idx_password_reset_tokens_expiration
    ON password_reset_tokens(expires_at);

CREATE INDEX idx_password_reset_tokens_user_used
    ON password_reset_tokens(user_id, used);

CREATE UNIQUE INDEX uq_password_reset_tokens_unused_user
    ON password_reset_tokens(user_id)
    WHERE used = false;