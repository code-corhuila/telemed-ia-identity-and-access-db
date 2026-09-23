-- ============================================================
-- Identity & Access
-- V7 - Add refresh token user index
-- ============================================================

CREATE INDEX idx_refresh_tokens_user
    ON refresh_tokens(user_id);