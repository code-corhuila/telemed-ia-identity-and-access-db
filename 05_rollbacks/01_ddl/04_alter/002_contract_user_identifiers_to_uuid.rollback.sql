-- Restore the UUID expand-phase state.

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

-- Every row must have its numeric relationship before restoring
-- BIGINT as the active foreign key.
ALTER TABLE refresh_tokens
    ALTER COLUMN legacy_user_id SET NOT NULL;

ALTER TABLE password_reset_tokens
    ALTER COLUMN legacy_user_id SET NOT NULL;

-- Remove UUID foreign keys from the contract state.
ALTER TABLE refresh_tokens
    DROP CONSTRAINT fk_refresh_tokens_user;

ALTER TABLE password_reset_tokens
    DROP CONSTRAINT fk_password_reset_tokens_user;

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