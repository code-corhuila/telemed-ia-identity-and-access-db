\set ON_ERROR_STOP on

SET application_name = 'identity-reset-first';
SET statement_timeout = '40s';
SET idle_in_transaction_session_timeout = '40s';

BEGIN ISOLATION LEVEL READ COMMITTED;

INSERT INTO password_reset_tokens (
    user_id,
    token_hash,
    expires_at
)
SELECT
    id,
    'concurrent-first',
    CURRENT_TIMESTAMP + INTERVAL '30 minutes'
FROM users
WHERE email = 'concurrent.reset.fixture@example.com';

-- Keep transaction A open after it has acquired the reset issuance
-- advisory lock. The runner verifies this state through pg_stat_activity
-- before starting transaction B.
SELECT pg_sleep(15);

COMMIT;