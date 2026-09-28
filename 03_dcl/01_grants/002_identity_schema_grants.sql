GRANT USAGE ON SCHEMA identity_and_access TO identity_reader, identity_writer;
REVOKE CREATE ON SCHEMA identity_and_access FROM identity_reader, identity_writer;
GRANT SELECT ON TABLE identity_and_access.roles, identity_and_access.users,
    identity_and_access.refresh_tokens, identity_and_access.password_reset_tokens
    TO identity_reader;
GRANT INSERT, UPDATE ON TABLE identity_and_access.users,
    identity_and_access.refresh_tokens, identity_and_access.password_reset_tokens
    TO identity_writer;
GRANT USAGE, SELECT ON SEQUENCE identity_and_access.users_id_seq,
    identity_and_access.refresh_tokens_id_seq,
    identity_and_access.password_reset_tokens_id_seq TO identity_writer;
REVOKE ALL ON FUNCTION identity_and_access.supersede_unused_password_reset_tokens()
    FROM PUBLIC;
GRANT EXECUTE ON FUNCTION identity_and_access.supersede_unused_password_reset_tokens()
    TO identity_writer;
