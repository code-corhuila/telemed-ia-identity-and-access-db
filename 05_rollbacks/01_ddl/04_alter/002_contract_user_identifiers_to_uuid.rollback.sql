-- Restore the UUID expand-phase state.

-- Reconstruct legacy numeric user identifiers for users created
-- after the UUID contract.
UPDATE users
SET legacy_id = nextval('users_id_seq'::regclass)
WHERE legacy_id IS NULL;

-- Fail explicitly if any user still lacks a numeric identifier.
DO $$
DECLARE
    missing_legacy_users BIGINT;
BEGIN
    SELECT COUNT(*)
    INTO missing_legacy_users
    FROM users
    WHERE legacy_id IS NULL;

    IF missing_legacy_users > 0 THEN
        RAISE EXCEPTION
            'UUID contract rollback failed: % users rows are missing legacy_id',
            missing_legacy_users;
    END IF;
END
$$;

-- Reconstruct numeric token relationships for rows created
-- after the UUID cutover.
UPDATE refresh_tokens rt
SET legacy_user_id = u.legacy_id
FROM users u
WHERE rt.user_id = u.id
  AND rt.legacy_user_id IS NULL;

UPDATE password_reset_tokens prt
SET legacy_user_id = u.legacy_id
FROM users u
WHERE prt.user_id = u.id
  AND prt.legacy_user_id IS NULL;

-- Validate token relationship reconstruction before restoring
-- BIGINT constraints.
DO $$
DECLARE
    missing_refresh_tokens BIGINT;
    missing_reset_tokens BIGINT;
BEGIN
    SELECT COUNT(*)
    INTO missing_refresh_tokens
    FROM refresh_tokens
    WHERE legacy_user_id IS NULL;

    SELECT COUNT(*)
    INTO missing_reset_tokens
    FROM password_reset_tokens
    WHERE legacy_user_id IS NULL;

    IF missing_refresh_tokens > 0 THEN
        RAISE EXCEPTION
            'UUID contract rollback failed: % refresh_tokens rows are missing legacy_user_id',
            missing_refresh_tokens;
    END IF;

    IF missing_reset_tokens > 0 THEN
        RAISE EXCEPTION
            'UUID contract rollback failed: % password_reset_tokens rows are missing legacy_user_id',
            missing_reset_tokens;
    END IF;
END
$$;

-- Restore required numeric relationships.
ALTER TABLE refresh_tokens
    ALTER COLUMN legacy_user_id SET NOT NULL;

ALTER TABLE password_reset_tokens
    ALTER COLUMN legacy_user_id SET NOT NULL;

-- Remove definitive UUID foreign keys.
ALTER TABLE refresh_tokens
    DROP CONSTRAINT fk_refresh_tokens_user_uuid;

ALTER TABLE password_reset_tokens
    DROP CONSTRAINT fk_password_reset_tokens_user_uuid;

-- Remove the UUID primary key and legacy uniqueness constraint.
ALTER TABLE users
    DROP CONSTRAINT users_pkey;

ALTER TABLE users
    DROP CONSTRAINT uq_users_legacy_id;

-- Restore expand-phase column names.
ALTER TABLE users
    RENAME COLUMN id TO id_uuid;

ALTER TABLE users
    RENAME COLUMN legacy_id TO id;

ALTER TABLE refresh_tokens
    RENAME COLUMN user_id TO user_id_uuid;

ALTER TABLE refresh_tokens
    RENAME COLUMN legacy_user_id TO user_id;

ALTER TABLE password_reset_tokens
    RENAME COLUMN user_id TO user_id_uuid;

ALTER TABLE password_reset_tokens
    RENAME COLUMN legacy_user_id TO user_id;

-- Restore BIGINT generation behavior from the expand phase.
ALTER TABLE users
    ALTER COLUMN id
    SET DEFAULT nextval('users_id_seq'::regclass);

ALTER TABLE users
    ALTER COLUMN id SET NOT NULL;

-- Restore BIGINT as the active primary key.
ALTER TABLE users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);

-- Restore UUID uniqueness required by the expand phase.
ALTER TABLE users
    ADD CONSTRAINT uq_users_id_uuid UNIQUE (id_uuid);

-- Restore the original BIGINT relationships.
ALTER TABLE refresh_tokens
    ADD CONSTRAINT fk_refresh_tokens_user
        FOREIGN KEY (user_id)
        REFERENCES users(id)
        ON DELETE RESTRICT;

ALTER TABLE password_reset_tokens
    ADD CONSTRAINT fk_password_reset_tokens_user
        FOREIGN KEY (user_id)
        REFERENCES users(id)
        ON DELETE RESTRICT;

-- Restore the parallel UUID relationships from the expand phase.
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