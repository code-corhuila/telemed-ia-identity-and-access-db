-- Serialize password-reset issuance inside an Identity-specific advisory-lock
-- namespace while keeping "used" distinct from "superseded".

CREATE OR REPLACE FUNCTION supersede_unused_password_reset_tokens()
RETURNS TRIGGER AS $$
BEGIN
    -- Terminal or already-superseded imports must not supersede
    -- the current active token.
    IF NEW.used OR NEW.superseded_at IS NOT NULL THEN
        RETURN NEW;
    END IF;

    -- Namespace 12001 is reserved by Identity & Access for
    -- password-reset issuance serialization.
    PERFORM pg_advisory_xact_lock(
        12001,
        hashtext(NEW.user_id::text)
    );

    UPDATE password_reset_tokens
    SET superseded_at = clock_timestamp()
    WHERE user_id = NEW.user_id
      AND used = FALSE
      AND superseded_at IS NULL;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
