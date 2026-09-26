CREATE UNIQUE INDEX uq_users_email_lower
    ON users (LOWER(email));

CREATE INDEX idx_users_role
    ON users(role_id);
