-- Complete the UUID identifier cutover.
-- UUID becomes the definitive public identifier while BIGINT values
-- are retained only for traceability and rollback support.

-- Remove both BIGINT and transitional UUID foreign keys
-- before switching the active identifiers.
ALTER TABLE refresh_tokens
    DROP CONSTRAINT fk_refresh_tokens_user;

ALTER TABLE password_reset_tokens
    DROP CONSTRAINT fk_password_reset_tokens_user;

ALTER TABLE refresh_tokens
    DROP CONSTRAINT fk_refresh_tokens_user_uuid;

ALTER TABLE password_reset_tokens
    DROP CONSTRAINT fk_password_reset_tokens_user_uuid;

-- UUID will become the primary key, so the temporary uniqueness
-- constraint from the expand phase is no longer required.
ALTER TABLE users
    DROP CONSTRAINT uq_users_id_uuid;

-- Remove the current BIGINT primary key.
ALTER TABLE users
    DROP CONSTRAINT users_pkey;

-- Switch users to UUID while retaining the previous numeric identifier.
ALTER TABLE users
    RENAME COLUMN id TO legacy_id;

ALTER TABLE users
    RENAME COLUMN id_uuid TO id;

-- The legacy numeric identifier must no longer participate in
-- new user creation.
ALTER TABLE users
    ALTER COLUMN legacy_id DROP DEFAULT;

ALTER TABLE users
    ALTER COLUMN legacy_id DROP NOT NULL;

-- Switch token relationships to UUID while retaining numeric references.
ALTER TABLE refresh_tokens
    RENAME COLUMN user_id TO legacy_user_id;

ALTER TABLE refresh_tokens
    RENAME COLUMN user_id_uuid TO user_id;

ALTER TABLE password_reset_tokens
    RENAME COLUMN user_id TO legacy_user_id;

ALTER TABLE password_reset_tokens
    RENAME COLUMN user_id_uuid TO user_id;

-- New token rows can now use only UUID relationships.
ALTER TABLE refresh_tokens
    ALTER COLUMN legacy_user_id DROP NOT NULL;

ALTER TABLE password_reset_tokens
    ALTER COLUMN legacy_user_id DROP NOT NULL;

-- Retained numeric identifiers remain unique when present.
ALTER TABLE users
    ADD CONSTRAINT uq_users_legacy_id UNIQUE (legacy_id);

-- UUID is now the definitive users primary key.
ALTER TABLE users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);

-- Rebuild token relationships explicitly as UUID foreign keys.
ALTER TABLE refresh_tokens
    ADD CONSTRAINT fk_refresh_tokens_user_uuid
        FOREIGN KEY (user_id)
        REFERENCES users(id)
        ON DELETE RESTRICT;

ALTER TABLE password_reset_tokens
    ADD CONSTRAINT fk_password_reset_tokens_user_uuid
        FOREIGN KEY (user_id)
        REFERENCES users(id)
        ON DELETE RESTRICT;