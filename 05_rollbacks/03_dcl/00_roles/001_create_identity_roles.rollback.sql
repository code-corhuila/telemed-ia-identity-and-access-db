DO $$
BEGIN
    -- Revoke only the membership created by this changeset.
    IF EXISTS (
        SELECT 1
        FROM pg_roles
        WHERE rolname = 'identity_reader'
    )
    AND EXISTS (
        SELECT 1
        FROM pg_roles
        WHERE rolname = 'identity_writer'
    ) THEN
        REVOKE identity_reader FROM identity_writer;
    END IF;

    -- Drop the writer role only when PostgreSQL confirms
    -- that it has no external dependencies.
    IF EXISTS (
        SELECT 1
        FROM pg_roles
        WHERE rolname = 'identity_writer'
    ) THEN
        BEGIN
            DROP ROLE identity_writer;
        EXCEPTION
            WHEN dependent_objects_still_exist THEN
                RAISE NOTICE
                    'Preserving identity_writer because external dependencies exist.';
        END;
    END IF;

    -- Drop the reader role only when PostgreSQL confirms
    -- that it has no external dependencies.
    IF EXISTS (
        SELECT 1
        FROM pg_roles
        WHERE rolname = 'identity_reader'
    ) THEN
        BEGIN
            DROP ROLE identity_reader;
        EXCEPTION
            WHEN dependent_objects_still_exist THEN
                RAISE NOTICE
                    'Preserving identity_reader because external dependencies exist.';
        END;
    END IF;
END
$$;