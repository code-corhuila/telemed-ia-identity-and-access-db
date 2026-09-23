-- ============================================================
-- Identity & Access
-- V6 - Fix password reset token lifecycle
-- ============================================================

CREATE OR REPLACE FUNCTION invalidate_expired_password_reset_tokens()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE password_reset_tokens
    SET used = TRUE
    WHERE user_id = NEW.user_id
      AND used = FALSE
      AND expires_at <= CURRENT_TIMESTAMP;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_invalidate_expired_password_reset_tokens
BEFORE INSERT ON password_reset_tokens
FOR EACH ROW
EXECUTE FUNCTION invalidate_expired_password_reset_tokens();