CREATE TABLE identity_idempotency_key (
    key_value TEXT NOT NULL,
    user_id UUID NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_identity_idempotency_key
        PRIMARY KEY (key_value),

    CONSTRAINT chk_identity_idempotency_key_length
        CHECK (char_length(key_value) BETWEEN 8 AND 128)
);
