DROP INDEX IF EXISTS uq_password_reset_tokens_unused_user;

CREATE UNIQUE INDEX uq_password_reset_tokens_unused_user
    ON password_reset_tokens(user_id)
    WHERE used = FALSE;
