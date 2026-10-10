-- Prepare password-reset state semantics for the hardening migration.
--
-- Existing superseded rows may still have used = TRUE, therefore the new
-- constraint is introduced as NOT VALID. A later data patch normalizes
-- historical rows and validates the constraint.

ALTER TABLE password_reset_tokens
    DROP CONSTRAINT IF EXISTS
        chk_password_reset_tokens_superseded_used;

ALTER TABLE password_reset_tokens
    ADD CONSTRAINT chk_password_reset_tokens_terminal_state
    CHECK (
        NOT (
            used = TRUE
            AND superseded_at IS NOT NULL
        )
    )
    NOT VALID;
