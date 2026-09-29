-- Serialize password-reset token issuance for the same user.
--
-- The user row acts as the serialization point. Concurrent issuers for the
-- same user must acquire the same row lock before superseding the previous
-- unused token.
--
-- Tokens already inserted as terminal (`used = TRUE`) must not supersede the
-- currently active recovery token.

CREATE OR REPLACE FUNCTION supersede_unused_password_reset_tokens()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.used THEN
        RETURN NEW;
    END IF;

    PERFORM 1
    FROM users
    WHERE id = NEW.user_id
    FOR NO KEY UPDATE;

    UPDATE password_reset_tokens
    SET
        used = TRUE,
        superseded_at = clock_timestamp()
    WHERE user_id = NEW.user_id
      AND used = FALSE;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;