\set ON_ERROR_STOP on

BEGIN;

-- ============================================================
-- TEST 1: expired unused token can be superseded
-- ============================================================

DO $$
DECLARE
    test_user_id UUID;
    expired_used BOOLEAN;
    expired_superseded_at TIMESTAMPTZ;
    replacement_used BOOLEAN;
    replacement_superseded_at TIMESTAMPTZ;
BEGIN
    INSERT INTO users (
        full_name,
        email,
        identity_document,
        role_id,
        password_hash
    )
    VALUES (
        'Expired Reset Fixture',
        'expired.reset.fixture@example.com',
        'EXPIRED-RESET-FIXTURE',
        (SELECT id FROM roles WHERE name = 'PATIENT'),
        'test-hash'
    )
    RETURNING id INTO test_user_id;

    INSERT INTO password_reset_tokens (
        user_id,
        token_hash,
        expires_at,
        used
    )
    VALUES (
        test_user_id,
        'expired-unused-fixture',
        CURRENT_TIMESTAMP - INTERVAL '30 minutes',
        FALSE
    );

    INSERT INTO password_reset_tokens (
        user_id,
        token_hash,
        expires_at,
        used
    )
    VALUES (
        test_user_id,
        'replacement-for-expired',
        CURRENT_TIMESTAMP + INTERVAL '30 minutes',
        FALSE
    );

    SELECT used, superseded_at
    INTO expired_used, expired_superseded_at
    FROM password_reset_tokens
    WHERE token_hash = 'expired-unused-fixture';

    SELECT used, superseded_at
    INTO replacement_used, replacement_superseded_at
    FROM password_reset_tokens
    WHERE token_hash = 'replacement-for-expired';

    IF expired_used IS DISTINCT FROM FALSE
       OR expired_superseded_at IS NULL THEN
        RAISE EXCEPTION
            'Expired unused token was not superseded';
    END IF;

    IF replacement_used IS DISTINCT FROM FALSE
       OR replacement_superseded_at IS NOT NULL THEN
        RAISE EXCEPTION
            'Replacement token is not active';
    END IF;
END
$$;

-- ============================================================
-- TEST 2: valid unused token is superseded
-- ============================================================

DO $$
DECLARE
    test_user_id UUID;
    previous_used BOOLEAN;
    previous_superseded_at TIMESTAMPTZ;
    latest_used BOOLEAN;
    latest_superseded_at TIMESTAMPTZ;
BEGIN
    INSERT INTO users (
        full_name,
        email,
        identity_document,
        role_id,
        password_hash
    )
    VALUES (
        'Valid Reset Fixture',
        'valid.reset.fixture@example.com',
        'VALID-RESET-FIXTURE',
        (SELECT id FROM roles WHERE name = 'PATIENT'),
        'test-hash'
    )
    RETURNING id INTO test_user_id;

    INSERT INTO password_reset_tokens (
        user_id,
        token_hash,
        expires_at,
        used
    )
    VALUES (
        test_user_id,
        'previous-valid-unused',
        CURRENT_TIMESTAMP + INTERVAL '20 minutes',
        FALSE
    );

    INSERT INTO password_reset_tokens (
        user_id,
        token_hash,
        expires_at,
        used
    )
    VALUES (
        test_user_id,
        'latest-valid-unused',
        CURRENT_TIMESTAMP + INTERVAL '30 minutes',
        FALSE
    );

    SELECT used, superseded_at
    INTO previous_used, previous_superseded_at
    FROM password_reset_tokens
    WHERE token_hash = 'previous-valid-unused';

    SELECT used, superseded_at
    INTO latest_used, latest_superseded_at
    FROM password_reset_tokens
    WHERE token_hash = 'latest-valid-unused';

    IF previous_used IS DISTINCT FROM FALSE
       OR previous_superseded_at IS NULL THEN
        RAISE EXCEPTION
            'Previous valid unused token was not superseded';
    END IF;

    IF latest_used IS DISTINCT FROM FALSE
       OR latest_superseded_at IS NOT NULL THEN
        RAISE EXCEPTION
            'Latest reset token is not active';
    END IF;
END
$$;

-- ============================================================
-- TEST 3: terminal token does not supersede active token
-- ============================================================

DO $$
DECLARE
    test_user_id UUID;
    active_used BOOLEAN;
    active_superseded_at TIMESTAMPTZ;
BEGIN
    INSERT INTO users (
        full_name,
        email,
        identity_document,
        role_id,
        password_hash
    )
    VALUES (
        'Terminal Reset Fixture',
        'terminal.reset.fixture@example.com',
        'TERMINAL-RESET-FIXTURE',
        (SELECT id FROM roles WHERE name = 'PATIENT'),
        'test-hash'
    )
    RETURNING id INTO test_user_id;

    INSERT INTO password_reset_tokens (
        user_id,
        token_hash,
        expires_at,
        used
    )
    VALUES (
        test_user_id,
        'active-before-terminal',
        CURRENT_TIMESTAMP + INTERVAL '30 minutes',
        FALSE
    );

    INSERT INTO password_reset_tokens (
        user_id,
        token_hash,
        expires_at,
        used
    )
    VALUES (
        test_user_id,
        'already-terminal-import',
        CURRENT_TIMESTAMP + INTERVAL '30 minutes',
        TRUE
    );

    SELECT used, superseded_at
    INTO active_used, active_superseded_at
    FROM password_reset_tokens
    WHERE token_hash = 'active-before-terminal';

    IF active_used IS DISTINCT FROM FALSE
       OR active_superseded_at IS NOT NULL THEN
        RAISE EXCEPTION
            'Terminal token incorrectly superseded active token';
    END IF;
END
$$;

-- ============================================================
-- TEST 4: integrity defenses remain installed
-- ============================================================

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_indexes
        WHERE schemaname = 'public'
          AND tablename = 'password_reset_tokens'
          AND indexname = 'uq_password_reset_tokens_unused_user'
          AND indexdef ILIKE '%UNIQUE%'
          AND indexdef ILIKE '%used = false%'
          AND indexdef ILIKE '%superseded_at IS NULL%'
    ) THEN
        RAISE EXCEPTION
            'Single-unused-token unique index is missing';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_password_reset_tokens_superseded_used'
          AND conrelid = 'password_reset_tokens'::regclass
    ) THEN
        RAISE EXCEPTION
            'Legacy superseded-used constraint remains installed';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_locks
        WHERE locktype = 'advisory'
          AND pid = pg_backend_pid()
          AND classid = 12001::oid
    ) THEN
        RAISE EXCEPTION
            'Reset issuance advisory lock is not namespaced';
    END IF;

    IF to_regprocedure(
        'invalidate_expired_password_reset_tokens()'
    ) IS NOT NULL THEN
        RAISE EXCEPTION
            'Legacy reset lifecycle function remains installed';
    END IF;
END
$$;

-- ============================================================
-- TEST: supersession trigger remains BEFORE INSERT
-- ============================================================

DO $$
DECLARE
    trigger_type SMALLINT;
BEGIN
    SELECT tgtype
    INTO trigger_type
    FROM pg_trigger
    WHERE tgname = 'trg_supersede_unused_password_reset_tokens'
      AND tgrelid = 'password_reset_tokens'::regclass
      AND NOT tgisinternal;

    IF trigger_type IS NULL THEN
        RAISE EXCEPTION
            'Supersession trigger is missing';
    END IF;

    -- PostgreSQL tgtype bitmask:
    -- BEFORE = 2
    -- INSERT = 4
    -- ROW = 1
    IF (trigger_type & 2) = 0
       OR (trigger_type & 4) = 0
       OR (trigger_type & 1) = 0 THEN
        RAISE EXCEPTION
            'Supersession trigger is not a BEFORE INSERT row trigger';
    END IF;
END
$$;

ROLLBACK;

\echo 'PASS: password reset lifecycle hardening'
