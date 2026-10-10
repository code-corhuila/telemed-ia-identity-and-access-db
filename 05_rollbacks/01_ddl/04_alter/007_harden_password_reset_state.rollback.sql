ALTER TABLE password_reset_tokens
    DROP CONSTRAINT IF EXISTS
        chk_password_reset_tokens_terminal_state;

ALTER TABLE password_reset_tokens
    ADD CONSTRAINT chk_password_reset_tokens_superseded_used
    CHECK (
        superseded_at IS NULL
        OR used = TRUE
    )
    NOT VALID;

ALTER TABLE password_reset_tokens
    VALIDATE CONSTRAINT chk_password_reset_tokens_superseded_used;
