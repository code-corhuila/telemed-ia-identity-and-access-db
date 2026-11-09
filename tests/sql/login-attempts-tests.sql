\set ON_ERROR_STOP on

BEGIN;

-- ============================================================
-- TEST 1: login attempts table structure
-- ============================================================

DO $$
DECLARE
    expected RECORD;
    actual_type TEXT;
    actual_nullable TEXT;
BEGIN
    IF to_regclass('public.login_attempts') IS NULL THEN
        RAISE EXCEPTION
            'TEST FAILED: table login_attempts does not exist';
    END IF;

    FOR expected IN
        SELECT *
        FROM (
            VALUES
                ('email_hash', 'character varying', 'NO'),
                ('failed_count', 'integer', 'NO'),
                ('window_started_at', 'timestamp with time zone', 'NO'),
                ('lockout_count', 'integer', 'NO'),
                ('locked_until', 'timestamp with time zone', 'YES'),
                ('updated_at', 'timestamp with time zone', 'NO')
        ) AS columns_expected(column_name, data_type, is_nullable)
    LOOP
        SELECT data_type, is_nullable
        INTO actual_type, actual_nullable
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'login_attempts'
          AND column_name = expected.column_name;

        IF actual_type IS DISTINCT FROM expected.data_type
           OR actual_nullable IS DISTINCT FROM expected.is_nullable THEN
            RAISE EXCEPTION
                'TEST FAILED: column % expected % nullable=%, found % nullable=%',
                expected.column_name,
                expected.data_type,
                expected.is_nullable,
                actual_type,
                actual_nullable;
        END IF;
    END LOOP;
END
$$;

-- ============================================================
-- TEST 2: defaults for a first failed attempt
-- ============================================================

DO $$
DECLARE
    recorded RECORD;
BEGIN
    INSERT INTO login_attempts (email_hash)
    VALUES (repeat('a', 64))
    RETURNING *
    INTO recorded;

    IF recorded.failed_count <> 0
       OR recorded.lockout_count <> 0
       OR recorded.locked_until IS NOT NULL
       OR recorded.window_started_at IS NULL
       OR recorded.updated_at IS NULL THEN
        RAISE EXCEPTION
            'TEST FAILED: unexpected defaults for a new login attempt row';
    END IF;

    BEGIN
        INSERT INTO login_attempts (email_hash)
        VALUES (repeat('a', 64));

        RAISE EXCEPTION
            'TEST FAILED: duplicate email_hash was accepted';
    EXCEPTION
        WHEN unique_violation THEN
            NULL;
    END;
END
$$;

-- ============================================================
-- TEST 3: invalid rows are rejected
-- ============================================================

DO $$
DECLARE
    invalid RECORD;
    rejected BOOLEAN;
BEGIN
    -- Only a lowercase SHA-256 hex digest is stored, never the raw email.
    FOR invalid IN
        SELECT *
        FROM (
            VALUES
                ('patient@example.com', 0, 0),
                (repeat('A', 64), 0, 0),
                (repeat('a', 63), 0, 0),
                (repeat('b', 64), -1, 0),
                (repeat('c', 64), 0, -1)
        ) AS rows_invalid(email_hash, failed_count, lockout_count)
    LOOP
        rejected := FALSE;

        BEGIN
            INSERT INTO login_attempts (email_hash, failed_count, lockout_count)
            VALUES (invalid.email_hash, invalid.failed_count, invalid.lockout_count);
        EXCEPTION
            WHEN check_violation THEN
                rejected := TRUE;
        END;

        IF NOT rejected THEN
            RAISE EXCEPTION
                'TEST FAILED: invalid row % was accepted', invalid;
        END IF;
    END LOOP;
END
$$;

-- ============================================================
-- TEST 4: least-privilege runtime grants
-- ============================================================

DO $$
BEGIN
    IF NOT has_table_privilege('identity_reader', 'public.login_attempts', 'SELECT')
       OR has_table_privilege('identity_reader', 'public.login_attempts', 'INSERT, UPDATE, DELETE') THEN
        RAISE EXCEPTION
            'TEST FAILED: identity_reader must only SELECT login_attempts';
    END IF;

    -- A successful login resets the counters with UPDATE; rows are never deleted.
    IF NOT has_table_privilege('identity_writer', 'public.login_attempts', 'SELECT')
       OR NOT has_table_privilege('identity_writer', 'public.login_attempts', 'INSERT')
       OR NOT has_table_privilege('identity_writer', 'public.login_attempts', 'UPDATE')
       OR has_table_privilege('identity_writer', 'public.login_attempts', 'DELETE') THEN
        RAISE EXCEPTION
            'TEST FAILED: identity_writer must SELECT, INSERT and UPDATE login_attempts, without DELETE';
    END IF;
END
$$;

ROLLBACK;
