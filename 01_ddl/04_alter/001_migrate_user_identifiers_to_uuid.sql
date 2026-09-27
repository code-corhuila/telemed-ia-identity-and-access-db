-- Expand identity identifiers with UUID columns while preserving
-- the existing BIGINT identifiers as the active keys.

ALTER TABLE users
    ADD COLUMN id_uuid UUID;

ALTER TABLE refresh_tokens
    ADD COLUMN user_id_uuid UUID;

ALTER TABLE password_reset_tokens
    ADD COLUMN user_id_uuid UUID;

-- Backfill UUID identifiers for existing users.
UPDATE users
SET id_uuid = gen_random_uuid()
WHERE id_uuid IS NULL;

-- Backfill UUID relationships for existing token rows.
UPDATE refresh_tokens rt
SET user_id_uuid = u.id_uuid
FROM users u
WHERE rt.user_id = u.id
  AND rt.user_id_uuid IS NULL;

UPDATE password_reset_tokens prt
SET user_id_uuid = u.id_uuid
FROM users u
WHERE prt.user_id = u.id
  AND prt.user_id_uuid IS NULL;

-- Verify that every row was migrated before adding NOT NULL constraints.
DO $$
DECLARE
    missing_users BIGINT;
    missing_refresh_tokens BIGINT;
    missing_reset_tokens BIGINT;
BEGIN
    SELECT COUNT(*)
    INTO missing_users
    FROM users
    WHERE id_uuid IS NULL;

    SELECT COUNT(*)
    INTO missing_refresh_tokens
    FROM refresh_tokens
    WHERE user_id_uuid IS NULL;

    SELECT COUNT(*)
    INTO missing_reset_tokens
    FROM password_reset_tokens
    WHERE user_id_uuid IS NULL;

    IF missing_users > 0 THEN
        RAISE EXCEPTION
            'UUID backfill failed for % users rows',
            missing_users;
    END IF;

    IF missing_refresh_tokens > 0 THEN
        RAISE EXCEPTION
            'UUID backfill failed for % refresh_tokens rows',
            missing_refresh_tokens;
    END IF;

    IF missing_reset_tokens > 0 THEN
        RAISE EXCEPTION
            'UUID backfill failed for % password_reset_tokens rows',
            missing_reset_tokens;
    END IF;
END
$$;

ALTER TABLE users
    ALTER COLUMN id_uuid SET NOT NULL;

ALTER TABLE refresh_tokens
    ALTER COLUMN user_id_uuid SET NOT NULL;

ALTER TABLE password_reset_tokens
    ALTER COLUMN user_id_uuid SET NOT NULL;

-- New users automatically receive a UUID while BIGINT id remains active.
ALTER TABLE users
    ALTER COLUMN id_uuid SET DEFAULT gen_random_uuid();

-- Keep UUID relationships consistent during the transition.
ALTER TABLE users
    ADD CONSTRAINT uq_users_id_uuid UNIQUE (id_uuid);

ALTER TABLE refresh_tokens
    ADD CONSTRAINT fk_refresh_tokens_user_uuid
        FOREIGN KEY (user_id_uuid)
        REFERENCES users(id_uuid)
        ON DELETE RESTRICT;

ALTER TABLE password_reset_tokens
    ADD CONSTRAINT fk_password_reset_tokens_user_uuid
        FOREIGN KEY (user_id_uuid)
        REFERENCES users(id_uuid)
        ON DELETE RESTRICT;