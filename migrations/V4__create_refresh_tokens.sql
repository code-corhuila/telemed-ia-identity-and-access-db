-- ============================================================
-- Identity & Access
-- V4 - Create refresh tokens table
-- ============================================================

CREATE TABLE refresh_tokens (
    id BIGSERIAL PRIMARY KEY,

    user_id BIGINT NOT NULL,

    token_hash VARCHAR(120) NOT NULL UNIQUE,

    expires_at TIMESTAMPTZ NOT NULL,

    revoked BOOLEAN NOT NULL DEFAULT FALSE,

    CONSTRAINT fk_refresh_tokens_user
        FOREIGN KEY (user_id)
        REFERENCES users(id)
        ON DELETE CASCADE
);

CREATE INDEX idx_refresh_tokens_user
    ON refresh_tokens(user_id);

CREATE INDEX idx_refresh_tokens_expiration
    ON refresh_tokens(expires_at);

CREATE INDEX idx_refresh_tokens_user_revoked
    ON refresh_tokens(user_id, revoked);