-- Migrate password-reset token identifiers from BIGINT to UUID.
-- The domain defines recoveryTokenId as a UUID identifier.

ALTER TABLE password_reset_tokens
    ADD COLUMN id_uuid UUID;

UPDATE password_reset_tokens
SET id_uuid = gen_random_uuid()
WHERE id_uuid IS NULL;

DO $$
DECLARE
    missing_ids BIGINT;
BEGIN
    SELECT COUNT(*)
    INTO missing_ids
    FROM password_reset_tokens
    WHERE id_uuid IS NULL;

    IF missing_ids > 0 THEN
        RAISE EXCEPTION
            'Password reset token UUID backfill failed for % rows',
            missing_ids;
    END IF;
END
$$;

ALTER TABLE password_reset_tokens
    ALTER COLUMN id_uuid SET NOT NULL;

ALTER TABLE password_reset_tokens
    ALTER COLUMN id_uuid SET DEFAULT gen_random_uuid();

ALTER TABLE password_reset_tokens
    DROP CONSTRAINT password_reset_tokens_pkey;

ALTER TABLE password_reset_tokens
    RENAME COLUMN id TO legacy_id;

ALTER TABLE password_reset_tokens
    RENAME COLUMN id_uuid TO id;

ALTER TABLE password_reset_tokens
    ALTER COLUMN legacy_id DROP DEFAULT;

ALTER TABLE password_reset_tokens
    ALTER COLUMN legacy_id DROP NOT NULL;

ALTER TABLE password_reset_tokens
    ADD CONSTRAINT uq_password_reset_tokens_legacy_id
        UNIQUE (legacy_id);

ALTER TABLE password_reset_tokens
    ADD CONSTRAINT password_reset_tokens_pkey
        PRIMARY KEY (id);