-- Rollback limitation:
-- password reset tokens created after the UUID cutover have no historical
-- BIGINT identifier to restore. During rollback, a new numeric legacy ID
-- is generated from password_reset_tokens_id_seq.
--
-- UUID identifiers issued after the cutover must therefore not be expected
-- to map to a pre-existing BIGINT identifier after rollback.
UPDATE password_reset_tokens
SET legacy_id = nextval('password_reset_tokens_id_seq'::regclass)
WHERE legacy_id IS NULL;

DO $$
DECLARE
    missing_legacy_ids BIGINT;
BEGIN
    SELECT COUNT(*)
    INTO missing_legacy_ids
    FROM password_reset_tokens
    WHERE legacy_id IS NULL;

    IF missing_legacy_ids > 0 THEN
        RAISE EXCEPTION
            'Password reset token rollback failed for % rows',
            missing_legacy_ids;
    END IF;
END
$$;

ALTER TABLE password_reset_tokens
    DROP CONSTRAINT password_reset_tokens_pkey;

ALTER TABLE password_reset_tokens
    DROP CONSTRAINT uq_password_reset_tokens_legacy_id;

ALTER TABLE password_reset_tokens
    RENAME COLUMN id TO id_uuid;

ALTER TABLE password_reset_tokens
    RENAME COLUMN legacy_id TO id;

ALTER TABLE password_reset_tokens
    ALTER COLUMN id
    SET DEFAULT nextval('password_reset_tokens_id_seq'::regclass);

ALTER TABLE password_reset_tokens
    ALTER COLUMN id SET NOT NULL;

ALTER TABLE password_reset_tokens
    ADD CONSTRAINT password_reset_tokens_pkey
        PRIMARY KEY (id);

ALTER TABLE password_reset_tokens
    DROP COLUMN id_uuid;