-- Record when a password reset token is superseded by a newer token.
-- A superseded token is terminal and therefore must also be marked as used.

ALTER TABLE password_reset_tokens
    ADD COLUMN superseded_at TIMESTAMPTZ;

ALTER TABLE password_reset_tokens
    ADD CONSTRAINT chk_password_reset_tokens_superseded_used
    CHECK (
        superseded_at IS NULL
        OR used = TRUE
    )
    NOT VALID;

ALTER TABLE password_reset_tokens
    VALIDATE CONSTRAINT chk_password_reset_tokens_superseded_used;