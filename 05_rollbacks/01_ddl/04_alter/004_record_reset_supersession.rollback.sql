-- Rollback safety:
-- superseded_at stores password-reset supersession history.
-- Do not silently discard that history if production data already uses it.

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM password_reset_tokens
        WHERE superseded_at IS NOT NULL
    ) THEN
        RAISE EXCEPTION
            'Rollback blocked: superseded_at contains password-reset history. Preserve or export the data before rollback.';
    END IF;
END
$$;

ALTER TABLE password_reset_tokens
    DROP CONSTRAINT IF EXISTS
        chk_password_reset_tokens_superseded_used;

ALTER TABLE password_reset_tokens
    DROP COLUMN IF EXISTS superseded_at;