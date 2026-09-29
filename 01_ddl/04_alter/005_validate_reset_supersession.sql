-- Validate the supersession integrity rule in a transaction
-- separate from the constraint creation.

ALTER TABLE password_reset_tokens
    VALIDATE CONSTRAINT chk_password_reset_tokens_superseded_used;