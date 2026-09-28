\set ON_ERROR_STOP on
SET search_path = pg_catalog;
DO $$
DECLARE t text; n integer;
BEGIN
    FOREACH t IN ARRAY ARRAY['roles','users','refresh_tokens','password_reset_tokens'] LOOP
        IF to_regclass('public.' || t) IS NOT NULL THEN
            RAISE EXCEPTION 'Domain relation remains in public: %', t;
        END IF;
        IF to_regclass('identity_and_access.' || t) IS NULL THEN
            RAISE EXCEPTION 'Domain relation missing: %', t;
        END IF;
    END LOOP;
    IF to_regprocedure('public.supersede_unused_password_reset_tokens()') IS NOT NULL
       OR to_regprocedure('public.invalidate_expired_password_reset_tokens()') IS NOT NULL THEN
        RAISE EXCEPTION 'Legacy lifecycle function remains in public';
    END IF;
    SELECT count(*) INTO n FROM pg_constraint c
    JOIN pg_class t ON t.oid = c.conrelid
    JOIN pg_namespace s ON s.oid = t.relnamespace
    JOIN pg_class parent ON parent.oid = c.confrelid
    WHERE s.nspname = 'identity_and_access' AND c.contype = 'f'
      AND parent.relnamespace <> t.relnamespace;
    IF n <> 0 THEN RAISE EXCEPTION 'Cross-schema foreign key'; END IF;
    IF EXISTS (SELECT 1 FROM pg_class c JOIN pg_depend d ON d.objid = c.oid
        JOIN pg_class t ON t.oid = d.refobjid
        WHERE c.relkind = 'S' AND t.relnamespace = 'identity_and_access'::regnamespace
          AND c.relnamespace <> t.relnamespace AND d.deptype IN ('a','i')) THEN
        RAISE EXCEPTION 'Owned sequence did not move';
    END IF;
    IF NOT has_schema_privilege('identity_reader','identity_and_access','USAGE')
       OR NOT has_schema_privilege('identity_writer','identity_and_access','USAGE') THEN
        RAISE EXCEPTION 'Missing domain schema USAGE';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_trigger
        WHERE tgrelid = 'identity_and_access.password_reset_tokens'::regclass
          AND tgfoid = 'identity_and_access.supersede_unused_password_reset_tokens()'::regprocedure
          AND NOT tgisinternal AND tgenabled = 'O') THEN
        RAISE EXCEPTION 'Lifecycle trigger did not move';
    END IF;
END $$;
-- With public absent, runtime writes and the trigger must still work.
BEGIN;
SET LOCAL ROLE identity_writer;
INSERT INTO identity_and_access.password_reset_tokens(user_id,token_hash,expires_at)
SELECT id, 'schema-path-explicit-token', '2099-01-01T00:00:00Z'
FROM identity_and_access.users WHERE email = 'identity.test@example.com';
ROLLBACK;
