\set ON_ERROR_STOP on

SET statement_timeout = '40s';

BEGIN ISOLATION LEVEL READ COMMITTED;

INSERT INTO password_reset_tokens (
    user_id,
    token_hash,
    expires_at
)
SELECT
    id,
    'concurrent-second',
    CURRENT_TIMESTAMP + INTERVAL '30 minutes'
FROM users
WHERE email = 'concurrent.reset.fixture@example.com';

COMMIT;