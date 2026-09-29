ALTER TABLE password_reset_tokens
    DROP CONSTRAINT IF EXISTS
        chk_password_reset_tokens_superseded_used;

ALTER TABLE password_reset_tokens
    DROP COLUMN IF EXISTS superseded_at;