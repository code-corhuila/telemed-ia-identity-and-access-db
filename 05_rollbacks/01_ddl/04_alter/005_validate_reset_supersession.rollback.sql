-- Return the constraint to its pre-validation state.

ALTER TABLE password_reset_tokens
    DROP CONSTRAINT chk_password_reset_tokens_superseded_used;

ALTER TABLE password_reset_tokens
    ADD CONSTRAINT chk_password_reset_tokens_superseded_used
    CHECK (
        superseded_at IS NULL
        OR used = TRUE
    )
    NOT VALID;