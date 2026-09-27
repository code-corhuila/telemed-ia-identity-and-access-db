-- Complete the UUID identifier cutover.
-- UUID becomes the active public identifier while BIGINT values
-- are retained temporarily for rollback and traceability.

-- Remove both BIGINT and UUID foreign keys before switching identifiers.
ALTER TABLE refresh_tokens
    DROP CONSTRAINT fk_refresh_tokens_user;

ALTER TABLE password_reset_tokens
    DROP CONSTRAINT fk_password_reset_tokens_user;

ALTER TABLE refresh_tokens
    DROP CONSTRAINT fk_refresh_tokens_user_uuid;

ALTER TABLE password_reset_tokens
    DROP CONSTRAINT fk_password_reset_tokens_user_uuid;

-- Remove the temporary UUID uniqueness constraint because UUID
-- will become the users primary key.
ALTER TABLE users
    DROP CONSTRAINT uq_users_id_uuid;

-- Remove the current BIGINT primary key.
ALTER TABLE users
    DROP CONSTRAINT users_pkey;

-- Switch users to UUID while retaining the numeric identifier.
ALTER TABLE users
    RENAME COLUMN id TO legacy_id;

ALTER TABLE users
    RENAME COLUMN id_uuid TO id;

-- Switch token relationships to UUID while retaining numeric references.
ALTER TABLE refresh_tokens
    RENAME COLUMN user_id TO legacy_user_id;

ALTER TABLE refresh_tokens
    RENAME COLUMN user_id_uuid TO user_id;

ALTER TABLE password_reset_tokens
    RENAME COLUMN user_id TO legacy_user_id;

ALTER TABLE password_reset_tokens
    RENAME COLUMN user_id_uuid TO user_id;

-- New token rows are allowed to use only the UUID relationship.
ALTER TABLE refresh_tokens
    ALTER COLUMN legacy_user_id DROP NOT NULL;

ALTER TABLE password_reset_tokens
    ALTER COLUMN legacy_user_id DROP NOT NULL;

-- Keep the numeric user identifier unique while it remains available.
ALTER TABLE users
    ADD CONSTRAINT uq_users_legacy_id UNIQUE (legacy_id);

-- UUID is now the definitive users primary key.
ALTER TABLE users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);

-- Rebuild token relationships against the UUID primary key.
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