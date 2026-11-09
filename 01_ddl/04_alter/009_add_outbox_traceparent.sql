-- The W3C traceparent of the request that recorded the event. The relay sends
-- it as an AMQP header so the consumer continues the same trace across the
-- broker. Optional: events recorded before this column, or outside an HTTP
-- request, have none. Only version 00 with lowercase hex is accepted, as
-- identity-api writes it.
ALTER TABLE identity_outbox_event
    ADD COLUMN traceparent VARCHAR(55);

ALTER TABLE identity_outbox_event
    ADD CONSTRAINT chk_identity_outbox_event_traceparent_format
        CHECK (
            traceparent IS NULL
            OR traceparent ~ '^00-[0-9a-f]{32}-[0-9a-f]{16}-[0-9a-f]{2}$'
        );
