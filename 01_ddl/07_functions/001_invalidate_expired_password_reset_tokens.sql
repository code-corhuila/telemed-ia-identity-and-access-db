CREATE OR REPLACE FUNCTION invalidate_expired_password_reset_tokens()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE password_reset_tokens
    SET used = TRUE
    WHERE user_id = NEW.user_id
      AND used = FALSE;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;