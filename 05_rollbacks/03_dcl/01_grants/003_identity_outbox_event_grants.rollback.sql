REVOKE SELECT
ON TABLE identity_outbox_event
FROM identity_reader;

REVOKE INSERT, UPDATE
ON TABLE identity_outbox_event
FROM identity_writer;
