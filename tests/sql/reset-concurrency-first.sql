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

-- Keep transaction A open so transaction B attempts to issue
-- another token for the same user while A still holds the lock.
SELECT pg_sleep(8);

COMMIT;