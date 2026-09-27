GRANT USAGE ON SCHEMA public TO identity_reader;
GRANT USAGE ON SCHEMA public TO identity_writer;

GRANT SELECT
ON TABLE roles, users, refresh_tokens, password_reset_tokens
TO identity_reader;

GRANT INSERT, UPDATE
ON TABLE users, refresh_tokens, password_reset_tokens
TO identity_writer;

GRANT USAGE, SELECT
ON SEQUENCE users_id_seq, refresh_tokens_id_seq, password_reset_tokens_id_seq
TO identity_writer;