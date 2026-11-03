-- Drops the stored trace context; events keep their correlation_id.
ALTER TABLE identity_outbox_event
    DROP CONSTRAINT IF EXISTS chk_identity_outbox_event_traceparent_format;

ALTER TABLE identity_outbox_event
    DROP COLUMN IF EXISTS traceparent;
