-- Supersede every previous unused password reset token for the
-- same user before a new recovery token is inserted.
--
-- Expiration validation remains an application responsibility.
-- This database rule guarantees that at most one unused recovery
-- token can remain active for a user after a new token is issued.

CREATE OR REPLACE FUNCTION supersede_unused_password_reset_tokens()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE password_reset_tokens
    SET used = TRUE
    WHERE user_id = NEW.user_id
      AND used = FALSE;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;