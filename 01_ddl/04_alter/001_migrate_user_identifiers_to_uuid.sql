-- Expand + switch user identifiers to UUID while retaining legacy numeric columns.

-- Add UUID identifiers.
ALTER TABLE users
    ADD COLUMN id_uuid UUID NOT NULL DEFAULT gen_random_uuid();

ALTER TABLE refresh_tokens
    ADD COLUMN user_id_uuid UUID;

ALTER TABLE password_reset_tokens
    ADD COLUMN user_id_uuid UUID;

-- Backfill UUID foreign keys from the existing numeric relationships.
UPDATE refresh_tokens rt
SET user_id_uuid = u.id_uuid
FROM users u
WHERE rt.user_id = u.id;

UPDATE password_reset_tokens prt
SET user_id_uuid = u.id_uuid
FROM users u
WHERE prt.user_id = u.id;

-- Every existing token must now have its UUID relationship populated.
ALTER TABLE refresh_tokens
    ALTER COLUMN user_id_uuid SET NOT NULL;

ALTER TABLE password_reset_tokens
    ALTER COLUMN user_id_uuid SET NOT NULL;

-- Remove constraints and indexes bound to the numeric user identifiers.
ALTER TABLE refresh_tokens
    DROP CONSTRAINT fk_refresh_tokens_user;

ALTER TABLE password_reset_tokens
    DROP CONSTRAINT fk_password_reset_tokens_user;

ALTER TABLE users
    DROP CONSTRAINT users_pkey;

-- Switch users to UUID while retaining the numeric identifier for compatibility.
ALTER TABLE users
    RENAME COLUMN id TO legacy_id;

ALTER TABLE users
    RENAME COLUMN id_uuid TO id;

-- Switch token relationships to UUID while retaining legacy numeric references.
ALTER TABLE refresh_tokens
    RENAME COLUMN user_id TO legacy_user_id;

ALTER TABLE refresh_tokens
    RENAME COLUMN user_id_uuid TO user_id;

ALTER TABLE password_reset_tokens
    RENAME COLUMN user_id TO legacy_user_id;

ALTER TABLE password_reset_tokens
    RENAME COLUMN user_id_uuid TO user_id;

-- New token rows may be created using only the UUID relationship.
ALTER TABLE refresh_tokens
    ALTER COLUMN legacy_user_id DROP NOT NULL;

ALTER TABLE password_reset_tokens
    ALTER COLUMN legacy_user_id DROP NOT NULL;

-- Rebuild primary key and compatibility index.
ALTER TABLE users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);

CREATE UNIQUE INDEX uq_users_legacy_id
    ON users(legacy_id);

-- Rebuild foreign keys against the UUID primary key.
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