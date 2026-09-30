\set ON_ERROR_STOP on

DELETE FROM password_reset_tokens
WHERE user_id IN (
    SELECT id
    FROM users
    WHERE email = 'concurrent.reset.fixture@example.com'
);

DELETE FROM users
WHERE email = 'concurrent.reset.fixture@example.com';

INSERT INTO users (
    full_name,
    email,
    identity_document,
    role_id,
    password_hash
)
VALUES (
    'Concurrent Reset Fixture',
    'concurrent.reset.fixture@example.com',
    'CONCURRENT-RESET-FIXTURE',
    (SELECT id FROM roles WHERE name = 'PATIENT'),
    'test-hash'
);