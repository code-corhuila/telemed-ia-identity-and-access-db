ALTER TABLE password_reset_tokens
    DROP CONSTRAINT IF EXISTS
        chk_password_reset_tokens_terminal_state;

UPDATE password_reset_tokens
SET used = TRUE
WHERE superseded_at IS NOT NULL
  AND used = FALSE;

ALTER TABLE password_reset_tokens
    ADD CONSTRAINT chk_password_reset_tokens_terminal_state
    CHECK (
        NOT (
            used = TRUE
            AND superseded_at IS NOT NULL
        )
    )
    NOT VALID;
