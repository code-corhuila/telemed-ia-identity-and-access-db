-- Normalize historical superseded reset tokens.
--
-- Before this change supersession was represented as:
--   used = TRUE, superseded_at IS NOT NULL
--
-- The definitive contract is:
--   used = FALSE, superseded_at IS NOT NULL

UPDATE password_reset_tokens
SET used = FALSE
WHERE superseded_at IS NOT NULL
  AND used = TRUE;

ALTER TABLE password_reset_tokens
    VALIDATE CONSTRAINT chk_password_reset_tokens_terminal_state;
