\set ON_ERROR_STOP on

-- Identity & Access DB - core schema validation

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

        RAISE EXCEPTION 'TEST FAILED: deactivated identity email was reused';

    EXCEPTION
        WHEN unique_violation THEN
            RAISE NOTICE 'PASS: deactivated identity remains reserved';
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
        RAISE EXCEPTION 'TEST FAILED: foreign bounded-context tables exist';
    END IF;

    RAISE NOTICE 'PASS: bounded context isolation is preserved';
END
$$;

-- TEST 9: expired password reset token must not block a new token
DO $$
DECLARE
    test_user_id UUID;
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
    RETURNING id INTO test_user_id;

    -- Create an expired token that is still marked as unused.
    INSERT INTO password_reset_tokens (
        user_id,
        token_hash,
        created_at,
        expires_at,
        used
    )
    VALUES (
        test_user_id,
        'expired-reset-token-hash',
        CURRENT_TIMESTAMP - INTERVAL '60 minutes',
        CURRENT_TIMESTAMP - INTERVAL '30 minutes',
        FALSE
    );

    -- Requesting a new token must invalidate the expired one
    -- and allow the new token to be inserted.
    INSERT INTO password_reset_tokens (
        user_id,
        token_hash,
        expires_at,
        used
    )
    VALUES (
        test_user_id,
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



-- TEST 10: public user identifier is UUID
DO $$
DECLARE
    id_type TEXT;
BEGIN
    SELECT data_type
    INTO id_type
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'users'
      AND column_name = 'id';

    IF id_type <> 'uuid' THEN
        RAISE EXCEPTION 'TEST FAILED: users.id must be UUID, found %', id_type;
    END IF;

    RAISE NOTICE 'PASS: users.id uses UUID';
END
$$;

DO $$
DECLARE
    users_id_type TEXT;
    refresh_user_id_type TEXT;
    reset_user_id_type TEXT;
BEGIN
    SELECT data_type
    INTO users_id_type
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'users'
      AND column_name = 'id';

    SELECT data_type
    INTO refresh_user_id_type
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'refresh_tokens'
      AND column_name = 'user_id';

    SELECT data_type
    INTO reset_user_id_type
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'password_reset_tokens'
      AND column_name = 'user_id';

    IF users_id_type <> 'uuid' THEN
        RAISE EXCEPTION 'users.id must use UUID';
    END IF;

    IF refresh_user_id_type <> 'uuid' THEN
        RAISE EXCEPTION 'refresh_tokens.user_id must use UUID';
    END IF;

    IF reset_user_id_type <> 'uuid' THEN
        RAISE EXCEPTION 'password_reset_tokens.user_id must use UUID';
    END IF;

    RAISE NOTICE 'PASS: identity relationships use UUID';
END
$$;

DO $$
DECLARE
    legacy_columns INTEGER;
BEGIN
    SELECT COUNT(*)
    INTO legacy_columns
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND (
          (table_name = 'users' AND column_name = 'legacy_id')
          OR
          (table_name = 'refresh_tokens' AND column_name = 'legacy_user_id')
          OR
          (table_name = 'password_reset_tokens' AND column_name = 'legacy_user_id')
      );

    IF legacy_columns <> 3 THEN
        RAISE EXCEPTION 'Expected all UUID compatibility columns to exist';
    END IF;

    RAISE NOTICE 'PASS: legacy identifier compatibility columns exist';
END
$$;

DO $$
DECLARE
    non_nullable_legacy_columns INTEGER;
BEGIN
    SELECT COUNT(*)
    INTO non_nullable_legacy_columns
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name IN ('refresh_tokens', 'password_reset_tokens')
      AND column_name = 'legacy_user_id'
      AND is_nullable = 'NO';

    IF non_nullable_legacy_columns <> 0 THEN
        RAISE EXCEPTION 'legacy_user_id must remain nullable after UUID migration';
    END IF;

    RAISE NOTICE 'PASS: legacy token identifiers are nullable';
END
$$;

-- ============================================================
-- UUID runtime insert validation
-- ============================================================

DO $$
DECLARE
    patient_role_id BIGINT;
    created_user_id UUID;
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
        'UUID Runtime Test',
        'uuid-runtime@example.com',
        'UUID-RUNTIME-001',
        patient_role_id,
        '$2a$10$testHashForUuidRuntimeValidation',
        FALSE,
        TRUE
    )
    RETURNING id INTO created_user_id;

    IF created_user_id IS NULL THEN
        RAISE EXCEPTION 'Expected UUID to be generated for a new user';
    END IF;

    INSERT INTO refresh_tokens (
        user_id,
        token_hash,
        expires_at
    )
    VALUES (
        created_user_id,
        'uuid-refresh-token-hash',
        CURRENT_TIMESTAMP + INTERVAL '7 days'
    );

    INSERT INTO password_reset_tokens (
        user_id,
        token_hash,
        expires_at
    )
    VALUES (
        created_user_id,
        'uuid-reset-token-hash',
        CURRENT_TIMESTAMP + INTERVAL '30 minutes'
    );

    IF NOT EXISTS (
        SELECT 1
        FROM refresh_tokens
        WHERE user_id = created_user_id
          AND token_hash = 'uuid-refresh-token-hash'
    ) THEN
        RAISE EXCEPTION 'Expected refresh token to persist with UUID user_id';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM password_reset_tokens
        WHERE user_id = created_user_id
          AND token_hash = 'uuid-reset-token-hash'
    ) THEN
        RAISE EXCEPTION 'Expected password reset token to persist with UUID user_id';
    END IF;

    RAISE NOTICE 'PASS: new users and tokens persist using UUID identifiers';
END
$$;


SELECT 'ALL CORE IDENTITY DATABASE TESTS PASSED' AS result;