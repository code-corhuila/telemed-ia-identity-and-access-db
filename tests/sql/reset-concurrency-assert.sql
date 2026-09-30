\set ON_ERROR_STOP on

DO $$
DECLARE
    active_count INTEGER;
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM password_reset_tokens
        WHERE token_hash = 'concurrent-first'
          AND used = TRUE
          AND superseded_at IS NOT NULL
    ) THEN
        RAISE EXCEPTION
            'First concurrent token was not superseded';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM password_reset_tokens
        WHERE token_hash = 'concurrent-second'
          AND used = FALSE
          AND superseded_at IS NULL
    ) THEN
        RAISE EXCEPTION
            'Second concurrent token is not the active token';
    END IF;

    SELECT COUNT(*)
    INTO active_count
    FROM password_reset_tokens t
    JOIN users u
        ON u.id = t.user_id
    WHERE u.email = 'concurrent.reset.fixture@example.com'
      AND t.used = FALSE;

    IF active_count <> 1 THEN
        RAISE EXCEPTION
            'Concurrent issuance left % unused tokens',
            active_count;
    END IF;
END
$$;

\echo 'PASS: concurrent reset issuance is serialized'