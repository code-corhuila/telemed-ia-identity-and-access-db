-- Roll back the UUID expansion while preserving the original
-- BIGINT identifiers and relationships.

ALTER TABLE password_reset_tokens
    DROP CONSTRAINT IF EXISTS fk_password_reset_tokens_user_uuid;

ALTER TABLE refresh_tokens
    DROP CONSTRAINT IF EXISTS fk_refresh_tokens_user_uuid;

ALTER TABLE users
    DROP CONSTRAINT IF EXISTS uq_users_id_uuid;

ALTER TABLE password_reset_tokens
    DROP COLUMN IF EXISTS user_id_uuid;

ALTER TABLE refresh_tokens
    DROP COLUMN IF EXISTS user_id_uuid;

ALTER TABLE users
    DROP COLUMN IF EXISTS id_uuid;