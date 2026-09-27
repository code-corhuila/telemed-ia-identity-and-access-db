DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_roles
        WHERE rolname = 'identity_reader'
    ) THEN
        CREATE ROLE identity_reader NOLOGIN;
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_roles
        WHERE rolname = 'identity_writer'
    ) THEN
        CREATE ROLE identity_writer NOLOGIN;
    END IF;
END
$$;

GRANT identity_reader TO identity_writer;