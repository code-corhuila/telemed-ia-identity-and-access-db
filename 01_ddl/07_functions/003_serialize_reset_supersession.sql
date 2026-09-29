-- Serialize password-reset token issuance for the same user
-- without locking rows in the users table.
--
-- A transaction-scoped advisory lock is keyed by user_id and released
-- automatically when the surrounding transaction ends.

CREATE OR REPLACE FUNCTION supersede_unused_password_reset_tokens()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.used THEN
        RETURN NEW;
    END IF;

    PERFORM pg_advisory_xact_lock(
        hashtextextended(NEW.user_id::text, 0)
    );

    UPDATE password_reset_tokens
    SET
        used = TRUE,
        superseded_at = clock_timestamp()
    WHERE user_id = NEW.user_id
      AND used = FALSE;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;