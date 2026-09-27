\set ON_ERROR_STOP on

-- ============================================================
-- Identity & Access DB - core schema validation
-- ============================================================

-- TEST 1: required roles exist
DO $$
DECLARE
    required_roles INTEGER;
BEGIN
    SELECT COUNT(*)
    INTO required_roles
    FROM roles
    WHERE name IN ('PATIENT', 'PROFESSIONAL', 'ADMIN');

    IF required_roles <> 3 THEN
        RAISE EXCEPTION 'TEST FAILED: required roles are missing';
    END IF;

    RAISE NOTICE 'PASS: required roles exist';
END
$$;


-- TEST 2: create a valid user
INSERT INTO users (
    full_name,
    email,
    identity_document,
    role_id,
    password_hash
)
VALUES (
    'Database Test User',
    'identity.test@example.com',
    'TEST-ID-001',
    (SELECT id FROM roles WHERE name = 'PATIENT'),
    'fake-password-hash'
);


-- TEST 3: user defaults
DO $$
DECLARE
    user_active BOOLEAN;
    user_verified BOOLEAN;
BEGIN
    SELECT active, verified
    INTO user_active, user_verified
    FROM users
    WHERE email = 'identity.test@example.com';

    IF user_active IS NOT TRUE THEN
        RAISE EXCEPTION 'TEST FAILED: active should default to true';
    END IF;

    IF user_verified IS NOT FALSE THEN
        RAISE EXCEPTION 'TEST FAILED: verified should default to false';
    END IF;

    RAISE NOTICE 'PASS: user defaults are correct';
END
$$;


-- TEST 4: email uniqueness is case-insensitive
DO $$
BEGIN
    BEGIN
        INSERT INTO users (
            full_name,
            email,
            identity_document,
            role_id,
            password_hash
        )
        VALUES (
            'Duplicate Email User',
            'IDENTITY.TEST@EXAMPLE.COM',
            'TEST-ID-002',
            (SELECT id FROM roles WHERE name = 'PATIENT'),
            'fake-password-hash'
        );

        RAISE EXCEPTION 'TEST FAILED: duplicate email was accepted';

    EXCEPTION
        WHEN unique_violation THEN
            RAISE NOTICE 'PASS: duplicate email was rejected';
    END;
END
$$;


-- TEST 5: identity document is unique
DO $$
BEGIN
    BEGIN
        INSERT INTO users (
            full_name,
            email,
            identity_document,
            role_id,
            password_hash
        )
        VALUES (
            'Duplicate Document User',
            'other.user@example.com',
            'TEST-ID-001',
            (SELECT id FROM roles WHERE name = 'PATIENT'),
            'fake-password-hash'
        );

        RAISE EXCEPTION 'TEST FAILED: duplicate document was accepted';

    EXCEPTION
        WHEN unique_violation THEN
            RAISE NOTICE 'PASS: duplicate document was rejected';
    END;
END
$$;


-- TEST 6: invalid role is rejected
DO $$
BEGIN
    BEGIN
        INSERT INTO users (
            full_name,
            email,
            identity_document,
            role_id,
            password_hash
        )
        VALUES (
            'Invalid Role User',
            'invalid.role@example.com',
            'TEST-ID-003',
            999999,
            'fake-password-hash'
        );

        RAISE EXCEPTION 'TEST FAILED: invalid role was accepted';

    EXCEPTION
        WHEN foreign_key_violation THEN
            RAISE NOTICE 'PASS: invalid role was rejected';
    END;
END
$$;


-- TEST 7: soft deactivation keeps identity reserved
UPDATE users
SET active = FALSE
WHERE email = 'identity.test@example.com';

DO $$
BEGIN
    BEGIN
        INSERT INTO users (
            full_name,
            email,
            identity_document,
            role_id,
            password_hash
        )
        VALUES (
            'Re-registration Test',
            'IDENTITY.TEST@EXAMPLE.COM',
            'TEST-ID-004',
            (SELECT id FROM roles WHERE name = 'PATIENT'),
            'fake-password-hash'
        );

        RAISE EXCEPTION
            'TEST FAILED: deactivated identity email was reused';

    EXCEPTION
        WHEN unique_violation THEN
            RAISE NOTICE
                'PASS: deactivated identity remains reserved';
    END;
END
$$;


-- TEST 8: bounded context isolation
DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.tables
        WHERE table_schema = 'public'
          AND table_name IN (
              'patients',
              'professionals',
              'appointments',
              'conversations',
              'notifications'
          )
    ) THEN
        RAISE EXCEPTION
            'TEST FAILED: foreign bounded-context tables exist';
    END IF;

    RAISE NOTICE 'PASS: bounded context isolation is preserved';
END
$$;


-- TEST 9: expired password reset token must not block a new token
DO $$
DECLARE
    test_user_id BIGINT;
    test_user_uuid UUID;
    expired_token_used BOOLEAN;
    active_token_count INTEGER;
BEGIN
    INSERT INTO users (
        full_name,
        email,
        identity_document,
        role_id,
        password_hash
    )
    VALUES (
        'Password Reset Test',
        'reset.lifecycle@example.com',
        'TEST-RESET-001',
        (SELECT id FROM roles WHERE name = 'PATIENT'),
        'fake-password-hash'
    )
    RETURNING id, id_uuid
    INTO test_user_id, test_user_uuid;

    INSERT INTO password_reset_tokens (
        user_id,
        user_id_uuid,
        token_hash,
        created_at,
        expires_at,
        used
    )
    VALUES (
        test_user_id,
        test_user_uuid,
        'expired-reset-token-hash',
        CURRENT_TIMESTAMP - INTERVAL '60 minutes',
        CURRENT_TIMESTAMP - INTERVAL '30 minutes',
        FALSE
    );

    INSERT INTO password_reset_tokens (
        user_id,
        user_id_uuid,
        token_hash,
        expires_at,
        used
    )
    VALUES (
        test_user_id,
        test_user_uuid,
        'new-reset-token-hash',
        CURRENT_TIMESTAMP + INTERVAL '30 minutes',
        FALSE
    );

    SELECT used
    INTO expired_token_used
    FROM password_reset_tokens
    WHERE token_hash = 'expired-reset-token-hash';

    IF expired_token_used IS DISTINCT FROM TRUE THEN
        RAISE EXCEPTION
            'TEST FAILED: expired password reset token was not invalidated';
    END IF;

    SELECT COUNT(*)
    INTO active_token_count
    FROM password_reset_tokens
    WHERE user_id = test_user_id
      AND used = FALSE;

    IF active_token_count <> 1 THEN
        RAISE EXCEPTION
            'TEST FAILED: expected exactly one unused password reset token, found %',
            active_token_count;
    END IF;

    RAISE NOTICE
        'PASS: expired password reset token does not block a new token';
END
$$;


-- ============================================================
-- TEST 10: UUID expansion keeps BIGINT active
-- ============================================================

DO $$
DECLARE
    users_id_type TEXT;
    users_uuid_type TEXT;
    refresh_user_id_type TEXT;
    refresh_uuid_type TEXT;
    reset_user_id_type TEXT;
    reset_uuid_type TEXT;
BEGIN
    SELECT data_type
    INTO users_id_type
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'users'
      AND column_name = 'id';

    SELECT data_type
    INTO users_uuid_type
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'users'
      AND column_name = 'id_uuid';

    SELECT data_type
    INTO refresh_user_id_type
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'refresh_tokens'
      AND column_name = 'user_id';

    SELECT data_type
    INTO refresh_uuid_type
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'refresh_tokens'
      AND column_name = 'user_id_uuid';

    SELECT data_type
    INTO reset_user_id_type
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'password_reset_tokens'
      AND column_name = 'user_id';

    SELECT data_type
    INTO reset_uuid_type
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'password_reset_tokens'
      AND column_name = 'user_id_uuid';

    IF users_id_type <> 'bigint' THEN
        RAISE EXCEPTION
            'TEST FAILED: users.id must remain BIGINT during UUID expansion';
    END IF;

    IF users_uuid_type <> 'uuid' THEN
        RAISE EXCEPTION
            'TEST FAILED: users.id_uuid must use UUID';
    END IF;

    IF refresh_user_id_type <> 'bigint' THEN
        RAISE EXCEPTION
            'TEST FAILED: refresh_tokens.user_id must remain BIGINT during UUID expansion';
    END IF;

    IF refresh_uuid_type <> 'uuid' THEN
        RAISE EXCEPTION
            'TEST FAILED: refresh_tokens.user_id_uuid must use UUID';
    END IF;

    IF reset_user_id_type <> 'bigint' THEN
        RAISE EXCEPTION
            'TEST FAILED: password_reset_tokens.user_id must remain BIGINT during UUID expansion';
    END IF;

    IF reset_uuid_type <> 'uuid' THEN
        RAISE EXCEPTION
            'TEST FAILED: password_reset_tokens.user_id_uuid must use UUID';
    END IF;

    RAISE NOTICE
        'PASS: BIGINT and UUID identifiers coexist during expansion';
END
$$;


-- ============================================================
-- TEST 11: UUID backfill is complete
-- ============================================================

DO $$
DECLARE
    users_without_uuid BIGINT;
    refresh_without_uuid BIGINT;
    reset_without_uuid BIGINT;
BEGIN
    SELECT COUNT(*)
    INTO users_without_uuid
    FROM users
    WHERE id_uuid IS NULL;

    SELECT COUNT(*)
    INTO refresh_without_uuid
    FROM refresh_tokens
    WHERE user_id_uuid IS NULL;

    SELECT COUNT(*)
    INTO reset_without_uuid
    FROM password_reset_tokens
    WHERE user_id_uuid IS NULL;

    IF users_without_uuid <> 0 THEN
        RAISE EXCEPTION
            'TEST FAILED: % users rows are missing id_uuid',
            users_without_uuid;
    END IF;

    IF refresh_without_uuid <> 0 THEN
        RAISE EXCEPTION
            'TEST FAILED: % refresh token rows are missing user_id_uuid',
            refresh_without_uuid;
    END IF;

    IF reset_without_uuid <> 0 THEN
        RAISE EXCEPTION
            'TEST FAILED: % password reset token rows are missing user_id_uuid',
            reset_without_uuid;
    END IF;

    RAISE NOTICE 'PASS: UUID backfill is complete';
END
$$;


-- ============================================================
-- TEST 12: BIGINT and UUID constraints coexist
-- ============================================================

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'users_pkey'
          AND conrelid = 'users'::regclass
          AND contype = 'p'
    ) THEN
        RAISE EXCEPTION
            'TEST FAILED: users primary key is missing';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'uq_users_id_uuid'
          AND conrelid = 'users'::regclass
          AND contype = 'u'
    ) THEN
        RAISE EXCEPTION
            'TEST FAILED: UUID user uniqueness constraint is missing';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'fk_refresh_tokens_user'
          AND conrelid = 'refresh_tokens'::regclass
          AND contype = 'f'
    ) THEN
        RAISE EXCEPTION
            'TEST FAILED: BIGINT refresh token foreign key is missing';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'fk_refresh_tokens_user_uuid'
          AND conrelid = 'refresh_tokens'::regclass
          AND contype = 'f'
    ) THEN
        RAISE EXCEPTION
            'TEST FAILED: UUID refresh token foreign key is missing';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'fk_password_reset_tokens_user'
          AND conrelid = 'password_reset_tokens'::regclass
          AND contype = 'f'
    ) THEN
        RAISE EXCEPTION
            'TEST FAILED: BIGINT password reset foreign key is missing';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'fk_password_reset_tokens_user_uuid'
          AND conrelid = 'password_reset_tokens'::regclass
          AND contype = 'f'
    ) THEN
        RAISE EXCEPTION
            'TEST FAILED: UUID password reset foreign key is missing';
    END IF;

    RAISE NOTICE
        'PASS: BIGINT and UUID key constraints coexist';
END
$$;


-- ============================================================
-- TEST 13: new users receive both identifiers
-- ============================================================

DO $$
DECLARE
    patient_role_id BIGINT;
    created_user_id BIGINT;
    created_user_uuid UUID;
BEGIN
    SELECT id
    INTO patient_role_id
    FROM roles
    WHERE name = 'PATIENT';

    INSERT INTO users (
        full_name,
        email,
        identity_document,
        role_id,
        password_hash,
        verified,
        active
    )
    VALUES (
        'UUID Expand Runtime Test',
        'uuid-expand@example.com',
        'UUID-EXPAND-001',
        patient_role_id,
        '$2a$10$testHashForUuidExpansion',
        FALSE,
        TRUE
    )
    RETURNING id, id_uuid
    INTO created_user_id, created_user_uuid;

    IF created_user_id IS NULL THEN
        RAISE EXCEPTION
            'TEST FAILED: expected BIGINT id for new user';
    END IF;

    IF created_user_uuid IS NULL THEN
        RAISE EXCEPTION
            'TEST FAILED: expected UUID id for new user';
    END IF;

    INSERT INTO refresh_tokens (
        user_id,
        user_id_uuid,
        token_hash,
        expires_at
    )
    VALUES (
        created_user_id,
        created_user_uuid,
        'uuid-expand-refresh-token',
        CURRENT_TIMESTAMP + INTERVAL '7 days'
    );

    INSERT INTO password_reset_tokens (
        user_id,
        user_id_uuid,
        token_hash,
        expires_at
    )
    VALUES (
        created_user_id,
        created_user_uuid,
        'uuid-expand-reset-token',
        CURRENT_TIMESTAMP + INTERVAL '30 minutes'
    );

    IF NOT EXISTS (
        SELECT 1
        FROM refresh_tokens
        WHERE user_id = created_user_id
          AND user_id_uuid = created_user_uuid
          AND token_hash = 'uuid-expand-refresh-token'
    ) THEN
        RAISE EXCEPTION
            'TEST FAILED: refresh token did not persist both identifiers';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM password_reset_tokens
        WHERE user_id = created_user_id
          AND user_id_uuid = created_user_uuid
          AND token_hash = 'uuid-expand-reset-token'
    ) THEN
        RAISE EXCEPTION
            'TEST FAILED: password reset token did not persist both identifiers';
    END IF;

    RAISE NOTICE
        'PASS: new rows persist with BIGINT and UUID identifiers';
END
$$;


SELECT 'ALL CORE IDENTITY DATABASE TESTS PASSED' AS result;