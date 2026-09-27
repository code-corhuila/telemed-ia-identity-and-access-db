REVOKE ALL PRIVILEGES
ON SEQUENCE users_id_seq, refresh_tokens_id_seq, password_reset_tokens_id_seq
FROM identity_writer;

REVOKE INSERT, UPDATE
ON TABLE users, refresh_tokens, password_reset_tokens
FROM identity_writer;

REVOKE SELECT
ON TABLE roles, users, refresh_tokens, password_reset_tokens
FROM identity_reader;

REVOKE USAGE ON SCHEMA public FROM identity_writer;
REVOKE USAGE ON SCHEMA public FROM identity_reader;