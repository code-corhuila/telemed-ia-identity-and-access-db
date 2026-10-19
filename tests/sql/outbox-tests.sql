\set ON_ERROR_STOP on

BEGIN;

-- ============================================================
-- TEST 1: outbox table structure
-- ============================================================

DO $$
DECLARE
    expected RECORD;
    actual_type TEXT;
    actual_nullable TEXT;
BEGIN
    IF to_regclass('public.identity_outbox_event') IS NULL THEN
        RAISE EXCEPTION
            'TEST FAILED: table identity_outbox_event does not exist';
    END IF;

    FOR expected IN
        SELECT *
        FROM (
            VALUES
                ('id', 'uuid', 'NO'),
                ('event_type', 'character varying', 'NO'),
                ('aggregate_id', 'uuid', 'NO'),
                ('payload', 'jsonb', 'NO'),
                ('correlation_id', 'character varying', 'YES'),
                ('event_version', 'smallint', 'NO'),
                ('occurred_at', 'timestamp with time zone', 'NO'),
                ('published_at', 'timestamp with time zone', 'YES'),
                ('attempts', 'integer', 'NO'),
                ('last_error', 'character varying', 'YES')
        ) AS columns_expected(column_name, data_type, is_nullable)
    LOOP
        SELECT data_type, is_nullable
        INTO actual_type, actual_nullable
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'identity_outbox_event'
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
-- TEST 2: defaults for a newly recorded event
-- ============================================================

DO $$
DECLARE
    recorded RECORD;
BEGIN
    INSERT INTO identity_outbox_event (
        event_type,
        aggregate_id,
        payload
    )
    VALUES (
        'PasswordRecoveryRequested',
        gen_random_uuid(),
        '{"email": "outbox.defaults@example.com"}'::jsonb
    )
    RETURNING *
    INTO recorded;

    IF recorded.id IS NULL
       OR recorded.event_version <> 1
       OR recorded.attempts <> 0
       OR recorded.occurred_at IS NULL
       OR recorded.published_at IS NOT NULL THEN
        RAISE EXCEPTION
            'TEST FAILED: unexpected defaults for a new outbox event';
    END IF;
END
$$;

-- ============================================================
-- TEST 3: invalid events are rejected
-- ============================================================

DO $$
DECLARE
    invalid_payload JSONB;
    rejected BOOLEAN;
BEGIN
    FOREACH invalid_payload IN ARRAY ARRAY[
        '[]'::jsonb,
        '"text"'::jsonb
    ]
    LOOP
        rejected := FALSE;

        BEGIN
            INSERT INTO identity_outbox_event (
                event_type,
                aggregate_id,
                payload
            )
            VALUES (
                'PasswordRecoveryRequested',
                gen_random_uuid(),
                invalid_payload
            );
        EXCEPTION
            WHEN check_violation THEN
                rejected := TRUE;
        END;

        IF NOT rejected THEN
            RAISE EXCEPTION
                'TEST FAILED: non-object payload % was accepted',
                invalid_payload;
        END IF;
    END LOOP;

    rejected := FALSE;

    BEGIN
        INSERT INTO identity_outbox_event (
            event_type,
            aggregate_id,
            payload
        )
        VALUES (
            '   ',
            gen_random_uuid(),
            '{}'::jsonb
        );
    EXCEPTION
        WHEN check_violation THEN
            rejected := TRUE;
    END;

    IF NOT rejected THEN
        RAISE EXCEPTION
            'TEST FAILED: blank event_type was accepted';
    END IF;

    rejected := FALSE;

    BEGIN
        INSERT INTO identity_outbox_event (
            event_type,
            aggregate_id,
            payload,
            attempts
        )
        VALUES (
            'PasswordRecoveryRequested',
            gen_random_uuid(),
            '{}'::jsonb,
            -1
        );
    EXCEPTION
        WHEN check_violation THEN
            rejected := TRUE;
    END;

    IF NOT rejected THEN
        RAISE EXCEPTION
            'TEST FAILED: negative attempts was accepted';
    END IF;

    rejected := FALSE;

    BEGIN
        INSERT INTO identity_outbox_event (
            event_type,
            aggregate_id,
            payload,
            event_version
        )
        VALUES (
            'PasswordRecoveryRequested',
            gen_random_uuid(),
            '{}'::jsonb,
            0
        );
    EXCEPTION
        WHEN check_violation THEN
            rejected := TRUE;
    END;

    IF NOT rejected THEN
        RAISE EXCEPTION
            'TEST FAILED: event_version 0 was accepted';
    END IF;
END
$$;

-- ============================================================
-- TEST 4: a published event cannot keep the reset link
-- ============================================================

DO $$
DECLARE
    event_id UUID;
    rejected BOOLEAN := FALSE;
    remaining_payload JSONB;
BEGIN
    INSERT INTO identity_outbox_event (
        event_type,
        aggregate_id,
        payload
    )
    VALUES (
        'PasswordRecoveryRequested',
        gen_random_uuid(),
        jsonb_build_object(
            'email', 'outbox.redaction@example.com',
            'resetUrl', 'https://example.com/reset?token=fixture'
        )
    )
    RETURNING id
    INTO event_id;

    BEGIN
        UPDATE identity_outbox_event
        SET published_at = CURRENT_TIMESTAMP
        WHERE id = event_id;
    EXCEPTION
        WHEN check_violation THEN
            rejected := TRUE;
    END;

    IF NOT rejected THEN
        RAISE EXCEPTION
            'TEST FAILED: event was marked published while still holding resetUrl';
    END IF;

    UPDATE identity_outbox_event
    SET published_at = CURRENT_TIMESTAMP,
        payload = payload - 'resetUrl'
    WHERE id = event_id
    RETURNING payload
    INTO remaining_payload;

    IF remaining_payload ? 'resetUrl'
       OR remaining_payload ->> 'email' IS DISTINCT FROM 'outbox.redaction@example.com' THEN
        RAISE EXCEPTION
            'TEST FAILED: redaction removed the wrong payload fields';
    END IF;
END
$$;

-- ============================================================
-- TEST 5: pending events index for the relay
-- ============================================================

DO $$
DECLARE
    index_definition TEXT;
BEGIN
    SELECT indexdef
    INTO index_definition
    FROM pg_indexes
    WHERE schemaname = 'public'
      AND tablename = 'identity_outbox_event'
      AND indexname = 'ix_identity_outbox_event_pending';

    IF index_definition IS NULL THEN
        RAISE EXCEPTION
            'TEST FAILED: index ix_identity_outbox_event_pending does not exist';
    END IF;

    IF index_definition NOT LIKE '%(occurred_at)%'
       OR index_definition NOT LIKE '%WHERE (published_at IS NULL)%' THEN
        RAISE EXCEPTION
            'TEST FAILED: unexpected pending index definition: %',
            index_definition;
    END IF;
END
$$;

-- ============================================================
-- TEST 6: least-privilege runtime grants
-- ============================================================

DO $$
BEGIN
    IF NOT has_table_privilege(
        'identity_reader',
        'public.identity_outbox_event',
        'SELECT'
    ) THEN
        RAISE EXCEPTION
            'TEST FAILED: identity_reader must SELECT identity_outbox_event';
    END IF;

    IF has_table_privilege(
        'identity_reader',
        'public.identity_outbox_event',
        'INSERT, UPDATE, DELETE'
    ) THEN
        RAISE EXCEPTION
            'TEST FAILED: identity_reader must not mutate identity_outbox_event';
    END IF;

    IF NOT has_table_privilege(
        'identity_writer',
        'public.identity_outbox_event',
        'SELECT'
    )
    OR NOT has_table_privilege(
        'identity_writer',
        'public.identity_outbox_event',
        'INSERT'
    )
    OR NOT has_table_privilege(
        'identity_writer',
        'public.identity_outbox_event',
        'UPDATE'
    ) THEN
        RAISE EXCEPTION
            'TEST FAILED: identity_writer must SELECT, INSERT and UPDATE identity_outbox_event';
    END IF;

    IF has_table_privilege(
        'identity_writer',
        'public.identity_outbox_event',
        'DELETE'
    ) THEN
        RAISE EXCEPTION
            'TEST FAILED: identity_writer must not DELETE identity_outbox_event';
    END IF;
END
$$;

ROLLBACK;

\echo 'PASS: identity outbox'
