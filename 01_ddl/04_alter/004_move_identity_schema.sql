SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';
-- SET SCHEMA preserves relation OIDs, grants, constraints and owned sequences.
ALTER TABLE public.roles SET SCHEMA identity_and_access;
ALTER TABLE public.users SET SCHEMA identity_and_access;
ALTER TABLE public.refresh_tokens SET SCHEMA identity_and_access;
ALTER TABLE public.password_reset_tokens SET SCHEMA identity_and_access;
ALTER FUNCTION public.supersede_unused_password_reset_tokens()
    SET SCHEMA identity_and_access;
CREATE OR REPLACE FUNCTION identity_and_access.supersede_unused_password_reset_tokens()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = pg_catalog
AS $$
BEGIN
    UPDATE identity_and_access.password_reset_tokens
    SET used = TRUE
    WHERE user_id = NEW.user_id AND used = FALSE;
    RETURN NEW;
END;
$$;
