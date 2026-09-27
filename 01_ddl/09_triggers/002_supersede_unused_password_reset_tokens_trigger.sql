-- Replace the original ambiguously named lifecycle trigger with
-- the explicit supersede-unused-token rule.

DROP TRIGGER IF EXISTS trg_invalidate_expired_password_reset_tokens
ON password_reset_tokens;

CREATE TRIGGER trg_supersede_unused_password_reset_tokens
BEFORE INSERT ON password_reset_tokens
FOR EACH ROW
EXECUTE FUNCTION supersede_unused_password_reset_tokens();