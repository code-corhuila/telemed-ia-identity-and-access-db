GRANT SELECT
ON TABLE identity_idempotency_key
TO identity_reader;

GRANT INSERT
ON TABLE identity_idempotency_key
TO identity_writer;
