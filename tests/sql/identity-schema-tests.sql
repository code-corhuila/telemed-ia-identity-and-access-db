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
    RETURNING id
    INTO test_user_id;

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

-- ============================================================
-- TEST 10: UUID contract is active
-- ============================================================

DO $$
DECLARE
    users_id_type TEXT;
    users_legacy_id_type TEXT;
    refresh_user_id_type TEXT;
    refresh_legacy_user_id_type TEXT;
    reset_user_id_type TEXT;
    reset_legacy_user_id_type TEXT;
BEGIN
    SELECT data_type
    INTO users_id_type
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'users'
      AND column_name = 'id';

    SELECT data_type
    INTO users_legacy_id_type
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'users'
      AND column_name = 'legacy_id';

    SELECT data_type
    INTO refresh_user_id_type
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'refresh_tokens'
      AND column_name = 'user_id';

    SELECT data_type
    INTO refresh_legacy_user_id_type
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'refresh_tokens'
      AND column_name = 'legacy_user_id';

    SELECT data_type
    INTO reset_user_id_type
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'password_reset_tokens'
      AND column_name = 'user_id';

    SELECT data_type
    INTO reset_legacy_user_id_type
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'password_reset_tokens'
      AND column_name = 'legacy_user_id';

    IF users_id_type <> 'uuid' THEN
        RAISE EXCEPTION
            'TEST FAILED: users.id must be UUID after contract';
    END IF;

    IF users_legacy_id_type <> 'bigint' THEN
        RAISE EXCEPTION
            'TEST FAILED: users.legacy_id must remain BIGINT';
    END IF;

    IF refresh_user_id_type <> 'uuid' THEN
        RAISE EXCEPTION
            'TEST FAILED: refresh_tokens.user_id must be UUID after contract';
    END IF;

    IF refresh_legacy_user_id_type <> 'bigint' THEN
        RAISE EXCEPTION
            'TEST FAILED: refresh_tokens.legacy_user_id must remain BIGINT';
    END IF;

    IF reset_user_id_type <> 'uuid' THEN
        RAISE EXCEPTION
            'TEST FAILED: password_reset_tokens.user_id must be UUID after contract';
    END IF;

    IF reset_legacy_user_id_type <> 'bigint' THEN
        RAISE EXCEPTION
            'TEST FAILED: password_reset_tokens.legacy_user_id must remain BIGINT';
    END IF;

    RAISE NOTICE
        'PASS: UUID contract is active and legacy identifiers are retained';
END
$$;


-- ============================================================
-- TEST 11: UUID key constraints are definitive
-- ============================================================

DO $$
DECLARE
    users_pk_definition TEXT;
    refresh_fk_definition TEXT;
    reset_fk_definition TEXT;
BEGIN
    SELECT pg_get_constraintdef(oid)
    INTO users_pk_definition
    FROM pg_constraint
    WHERE conname = 'users_pkey'
      AND conrelid = 'users'::regclass
      AND contype = 'p';

    IF users_pk_definition IS NULL
       OR users_pk_definition NOT LIKE '%(id)%' THEN
        RAISE EXCEPTION
            'TEST FAILED: users primary key must reference UUID id';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'uq_users_legacy_id'
          AND conrelid = 'users'::regclass
          AND contype = 'u'
    ) THEN
        RAISE EXCEPTION
            'TEST FAILED: users.legacy_id uniqueness constraint is missing';
    END IF;

    SELECT pg_get_constraintdef(oid)
    INTO refresh_fk_definition
    FROM pg_constraint
    WHERE conname = 'fk_refresh_tokens_user'
      AND conrelid = 'refresh_tokens'::regclass
      AND contype = 'f';

    IF refresh_fk_definition IS NULL
       OR refresh_fk_definition NOT LIKE '%FOREIGN KEY (user_id)%REFERENCES users(id)%' THEN
        RAISE EXCEPTION
            'TEST FAILED: refresh_tokens.user_id must reference users(id)';
    END IF;

    SELECT pg_get_constraintdef(oid)
    INTO reset_fk_definition
    FROM pg_constraint
    WHERE conname = 'fk_password_reset_tokens_user'
      AND conrelid = 'password_reset_tokens'::regclass
      AND contype = 'f';

    IF reset_fk_definition IS NULL
       OR reset_fk_definition NOT LIKE '%FOREIGN KEY (user_id)%REFERENCES users(id)%' THEN
        RAISE EXCEPTION
            'TEST FAILED: password_reset_tokens.user_id must reference users(id)';
    END IF;

    RAISE NOTICE
        'PASS: UUID primary and foreign keys are definitive';
END
$$;


-- ============================================================
-- TEST 12: legacy token identifiers are optional after contract
-- ============================================================

DO $$
DECLARE
    non_nullable_legacy_columns INTEGER;
BEGIN
    SELECT COUNT(*)
    INTO non_nullable_legacy_columns
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name IN (
          'refresh_tokens',
          'password_reset_tokens'
      )
      AND column_name = 'legacy_user_id'
      AND is_nullable = 'NO';

    IF non_nullable_legacy_columns <> 0 THEN
        RAISE EXCEPTION
            'TEST FAILED: legacy_user_id must be nullable after UUID contract';
    END IF;

    RAISE NOTICE
        'PASS: legacy token identifiers are optional after contract';
END
$$;


-- ============================================================
-- TEST 13: new runtime rows use UUID identifiers
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
        'UUID Contract Runtime Test',
        'uuid-contract@example.com',
        'UUID-CONTRACT-001',
        patient_role_id,
        '$2a$10$testHashForUuidContract',
        FALSE,
        TRUE
    )
    RETURNING id
    INTO created_user_id;

    IF created_user_id IS NULL THEN
        RAISE EXCEPTION
            'TEST FAILED: expected UUID id for new user';
    END IF;

    INSERT INTO refresh_tokens (
        user_id,
        token_hash,
        expires_at
    )
    VALUES (
        created_user_id,
        'uuid-contract-refresh-token',
        CURRENT_TIMESTAMP + INTERVAL '7 days'
    );

    INSERT INTO password_reset_tokens (
        user_id,
        token_hash,
        expires_at
    )
    VALUES (
        created_user_id,
        'uuid-contract-reset-token',
        CURRENT_TIMESTAMP + INTERVAL '30 minutes'
    );

    IF NOT EXISTS (
        SELECT 1
        FROM refresh_tokens
        WHERE user_id = created_user_id
          AND token_hash = 'uuid-contract-refresh-token'
    ) THEN
        RAISE EXCEPTION
            'TEST FAILED: refresh token did not persist UUID relationship';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM password_reset_tokens
        WHERE user_id = created_user_id
          AND token_hash = 'uuid-contract-reset-token'
    ) THEN
        RAISE EXCEPTION
            'TEST FAILED: password reset token did not persist UUID relationship';
    END IF;

    RAISE NOTICE
        'PASS: new runtime rows use UUID identifiers';
END
$$;

-- ============================================================
-- TEST 14: database access roles are NOLOGIN
-- ============================================================

DO $$
DECLARE
    reader_can_login BOOLEAN;
    writer_can_login BOOLEAN;
BEGIN
    SELECT rolcanlogin
    INTO reader_can_login
    FROM pg_roles
    WHERE rolname = 'identity_reader';

    SELECT rolcanlogin
    INTO writer_can_login
    FROM pg_roles
    WHERE rolname = 'identity_writer';

    IF reader_can_login IS DISTINCT FROM FALSE THEN
        RAISE EXCEPTION
            'TEST FAILED: identity_reader must be NOLOGIN';
    END IF;

    IF writer_can_login IS DISTINCT FROM FALSE THEN
        RAISE EXCEPTION
            'TEST FAILED: identity_writer must be NOLOGIN';
    END IF;

    RAISE NOTICE
        'PASS: database access roles are NOLOGIN';
END
$$;


-- ============================================================
-- TEST 15: writer inherits reader privileges
-- ============================================================

DO $$
BEGIN
    IF NOT pg_has_role(
        'identity_writer',
        'identity_reader',
        'MEMBER'
    ) THEN
        RAISE EXCEPTION
            'TEST FAILED: identity_writer must inherit identity_reader';
    END IF;

    RAISE NOTICE
        'PASS: identity_writer inherits identity_reader';
END
$$;


-- ============================================================
-- TEST 16: least-privilege table grants are enforced
-- ============================================================

DO $$
BEGIN
    -- Reader must be able to read all Identity & Access tables.
    IF NOT has_table_privilege(
        'identity_reader',
        'public.roles',
        'SELECT'
    ) THEN
        RAISE EXCEPTION
            'TEST FAILED: identity_reader must SELECT roles';
    END IF;

    IF NOT has_table_privilege(
        'identity_reader',
        'public.users',
        'SELECT'
    ) THEN
        RAISE EXCEPTION
            'TEST FAILED: identity_reader must SELECT users';
    END IF;

    IF NOT has_table_privilege(
        'identity_reader',
        'public.refresh_tokens',
        'SELECT'
    ) THEN
        RAISE EXCEPTION
            'TEST FAILED: identity_reader must SELECT refresh_tokens';
    END IF;

    IF NOT has_table_privilege(
        'identity_reader',
        'public.password_reset_tokens',
        'SELECT'
    ) THEN
        RAISE EXCEPTION
            'TEST FAILED: identity_reader must SELECT password_reset_tokens';
    END IF;

    -- Reader must not mutate domain data.
    IF has_table_privilege(
        'identity_reader',
        'public.users',
        'INSERT, UPDATE, DELETE'
    ) THEN
        RAISE EXCEPTION
            'TEST FAILED: identity_reader has mutation privileges';
    END IF;

    -- Writer must be able to write mutable Identity tables.
    IF NOT has_table_privilege(
        'identity_writer',
        'public.users',
        'INSERT'
    )
    OR NOT has_table_privilege(
        'identity_writer',
        'public.users',
        'UPDATE'
    ) THEN
        RAISE EXCEPTION
            'TEST FAILED: identity_writer must INSERT and UPDATE users';
    END IF;

    IF NOT has_table_privilege(
        'identity_writer',
        'public.refresh_tokens',
        'INSERT'
    )
    OR NOT has_table_privilege(
        'identity_writer',
        'public.refresh_tokens',
        'UPDATE'
    ) THEN
        RAISE EXCEPTION
            'TEST FAILED: identity_writer must INSERT and UPDATE refresh_tokens';
    END IF;

    IF NOT has_table_privilege(
        'identity_writer',
        'public.password_reset_tokens',
        'INSERT'
    )
    OR NOT has_table_privilege(
        'identity_writer',
        'public.password_reset_tokens',
        'UPDATE'
    ) THEN
        RAISE EXCEPTION
            'TEST FAILED: identity_writer must INSERT and UPDATE password_reset_tokens';
    END IF;

    -- Runtime roles must not delete identity data.
    IF has_table_privilege(
        'identity_writer',
        'public.users',
        'DELETE'
    )
    OR has_table_privilege(
        'identity_writer',
        'public.refresh_tokens',
        'DELETE'
    )
    OR has_table_privilege(
        'identity_writer',
        'public.password_reset_tokens',
        'DELETE'
    ) THEN
        RAISE EXCEPTION
            'TEST FAILED: identity_writer must not have DELETE privileges';
    END IF;

    RAISE NOTICE
        'PASS: least-privilege table grants are enforced';
END
$$;


-- ============================================================
-- TEST 17: runtime roles cannot perform DDL and writer can use sequences
-- ============================================================

DO $$
BEGIN
    -- Runtime roles may use the schema, but must not create objects in it.
    IF has_schema_privilege(
        'identity_reader',
        'public',
        'CREATE'
    ) THEN
        RAISE EXCEPTION
            'TEST FAILED: identity_reader must not CREATE objects in public schema';
    END IF;

    IF has_schema_privilege(
        'identity_writer',
        'public',
        'CREATE'
    ) THEN
        RAISE EXCEPTION
            'TEST FAILED: identity_writer must not CREATE objects in public schema';
    END IF;

    -- Writer needs sequences for BIGSERIAL identifiers during the expand phase.
    IF NOT has_sequence_privilege(
        'identity_writer',
        'public.users_id_seq',
        'USAGE'
    )
    OR NOT has_sequence_privilege(
        'identity_writer',
        'public.refresh_tokens_id_seq',
        'USAGE'
    )
    OR NOT has_sequence_privilege(
        'identity_writer',
        'public.password_reset_tokens_id_seq',
        'USAGE'
    ) THEN
        RAISE EXCEPTION
            'TEST FAILED: identity_writer is missing required sequence privileges';
    END IF;

    RAISE NOTICE
        'PASS: runtime DDL is restricted and sequence access is correct';
END
$$;

-- ============================================================
-- TEST 18: runtime roles enforce privileges in practice
-- ============================================================

DO $$
BEGIN
    -- Reader can SELECT.
    SET LOCAL ROLE identity_reader;
    PERFORM COUNT(*) FROM users;
    RESET ROLE;

    -- Reader cannot INSERT.
    BEGIN
        SET LOCAL ROLE identity_reader;

        INSERT INTO users (
            full_name,
            email,
            identity_document,
            role_id,
            password_hash
        )
        VALUES (
            'Unauthorized Reader Insert',
            'reader.insert@example.com',
            'READER-INSERT-001',
            (SELECT id FROM roles WHERE name = 'PATIENT'),
            'fake-password-hash'
        );

        RAISE EXCEPTION
            'TEST FAILED: identity_reader was able to INSERT users';

    EXCEPTION
        WHEN insufficient_privilege THEN
            RESET ROLE;
    END;

    -- Writer cannot DELETE.
    BEGIN
        SET LOCAL ROLE identity_writer;

        DELETE FROM users
        WHERE email = 'identity.test@example.com';

        RAISE EXCEPTION
            'TEST FAILED: identity_writer was able to DELETE users';

    EXCEPTION
        WHEN insufficient_privilege THEN
            RESET ROLE;
    END;

    -- Reader cannot create schema objects.
    BEGIN
        SET LOCAL ROLE identity_reader;

        CREATE TABLE unauthorized_reader_table (
            id BIGINT
        );

        RAISE EXCEPTION
            'TEST FAILED: identity_reader was able to CREATE TABLE';

    EXCEPTION
        WHEN insufficient_privilege THEN
            RESET ROLE;
    END;

    -- Writer cannot create schema objects.
    BEGIN
        SET LOCAL ROLE identity_writer;

        CREATE TABLE unauthorized_writer_table (
            id BIGINT
        );

        RAISE EXCEPTION
            'TEST FAILED: identity_writer was able to CREATE TABLE';

    EXCEPTION
        WHEN insufficient_privilege THEN
            RESET ROLE;
    END;

    RAISE NOTICE
        'PASS: runtime access roles enforce least privilege in practice';
END
$$;


SELECT 'ALL CORE IDENTITY DATABASE TESTS PASSED' AS result;