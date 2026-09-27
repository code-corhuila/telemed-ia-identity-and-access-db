-- Restore legacy numeric user identifiers while preserving rows
-- created after the UUID migration.

-- Reconstruct missing numeric relationships for token rows created
-- after the UUID switch.
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

-- Numeric relationships must be complete before restoring them
-- as the active foreign-key columns.
ALTER TABLE refresh_tokens
    ALTER COLUMN legacy_user_id SET NOT NULL;

ALTER TABLE password_reset_tokens
    ALTER COLUMN legacy_user_id SET NOT NULL;

-- Remove UUID foreign keys created by this migration.
ALTER TABLE refresh_tokens
    DROP CONSTRAINT fk_refresh_tokens_user;

ALTER TABLE password_reset_tokens
    DROP CONSTRAINT fk_password_reset_tokens_user;

-- Remove only the compatibility index created by this migration.
DROP INDEX IF EXISTS uq_users_legacy_id;

ALTER TABLE users
    DROP CONSTRAINT users_pkey;

-- Restore the original numeric identifiers.
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

-- Restore the numeric primary key.
ALTER TABLE users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);

-- Restore numeric foreign keys.
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

-- UUID compatibility columns are no longer needed after rollback.
ALTER TABLE users
    DROP COLUMN id_uuid;

ALTER TABLE refresh_tokens
    DROP COLUMN user_id_uuid;

ALTER TABLE password_reset_tokens
    DROP COLUMN user_id_uuid;