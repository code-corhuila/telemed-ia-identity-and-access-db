REVOKE SELECT
ON TABLE identity_idempotency_key
FROM identity_reader;

REVOKE INSERT
ON TABLE identity_idempotency_key
FROM identity_writer;
