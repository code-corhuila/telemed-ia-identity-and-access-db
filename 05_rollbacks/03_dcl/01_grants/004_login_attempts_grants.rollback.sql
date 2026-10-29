REVOKE SELECT
ON TABLE login_attempts
FROM identity_reader;

REVOKE INSERT, UPDATE
ON TABLE login_attempts
FROM identity_writer;
