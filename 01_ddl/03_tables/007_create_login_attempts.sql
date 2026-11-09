-- Failed-login counter per account for the per-account lock (STRIDE S,
-- telemed-ia-docs#152).
--
-- The key is the SHA-256 hex digest of the normalized email, so unknown
-- emails are counted too (the 429 answer does not reveal which accounts
-- exist) and the raw email is never stored. lockout_count drives the growing
-- delay (1, 5, then 15 minutes); a successful login resets the row with
-- UPDATE, so the runtime roles never DELETE.
CREATE TABLE login_attempts (
    email_hash VARCHAR(64) NOT NULL,
    failed_count INTEGER NOT NULL DEFAULT 0,
    window_started_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    lockout_count INTEGER NOT NULL DEFAULT 0,
    locked_until TIMESTAMPTZ,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_login_attempts
        PRIMARY KEY (email_hash),

    CONSTRAINT chk_login_attempts_email_hash_sha256
        CHECK (email_hash ~ '^[0-9a-f]{64}$'),

    CONSTRAINT chk_login_attempts_failed_count_not_negative
        CHECK (failed_count >= 0),

    CONSTRAINT chk_login_attempts_lockout_count_not_negative
        CHECK (lockout_count >= 0)
);
