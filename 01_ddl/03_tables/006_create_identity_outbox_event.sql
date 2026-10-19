-- Transactional outbox for Identity & Access integration events.
--
-- The API records the event in the same transaction as the business change
-- and a relay publishes it to the broker afterwards. PasswordRecoveryRequested
-- carries resetUrl, which contains the raw one-time reset token: the relay
-- must strip it from the payload when it marks the event as published, and
-- chk_identity_outbox_event_redacted_when_published enforces it.
CREATE TABLE identity_outbox_event (
    id UUID NOT NULL DEFAULT gen_random_uuid(),
    event_type VARCHAR(100) NOT NULL,
    aggregate_id UUID NOT NULL,
    payload JSONB NOT NULL,
    correlation_id VARCHAR(64),
    event_version SMALLINT NOT NULL DEFAULT 1,
    occurred_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    published_at TIMESTAMPTZ,
    attempts INTEGER NOT NULL DEFAULT 0,
    last_error VARCHAR(500),

    CONSTRAINT pk_identity_outbox_event
        PRIMARY KEY (id),

    CONSTRAINT chk_identity_outbox_event_type_not_blank
        CHECK (btrim(event_type) <> ''),

    CONSTRAINT chk_identity_outbox_event_payload_object
        CHECK (jsonb_typeof(payload) = 'object'),

    CONSTRAINT chk_identity_outbox_event_version_positive
        CHECK (event_version >= 1),

    CONSTRAINT chk_identity_outbox_event_attempts_not_negative
        CHECK (attempts >= 0),

    -- payload -> 'resetUrl' instead of the ? operator: JDBC drivers read ?
    -- as a bind parameter.
    CONSTRAINT chk_identity_outbox_event_redacted_when_published
        CHECK (published_at IS NULL OR payload -> 'resetUrl' IS NULL)
);
