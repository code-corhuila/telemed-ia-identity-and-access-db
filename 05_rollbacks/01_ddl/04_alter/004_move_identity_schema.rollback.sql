SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';
ALTER TABLE identity_and_access.roles SET SCHEMA public;
ALTER TABLE identity_and_access.users SET SCHEMA public;
ALTER TABLE identity_and_access.refresh_tokens SET SCHEMA public;
ALTER TABLE identity_and_access.password_reset_tokens SET SCHEMA public;
ALTER FUNCTION identity_and_access.supersede_unused_password_reset_tokens()
    SET SCHEMA public;
ALTER FUNCTION public.supersede_unused_password_reset_tokens() RESET ALL;
CREATE OR REPLACE FUNCTION public.supersede_unused_password_reset_tokens()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    UPDATE public.password_reset_tokens
    SET used = TRUE
    WHERE user_id = NEW.user_id AND used = FALSE;
    RETURN NEW;
END;
$$;
