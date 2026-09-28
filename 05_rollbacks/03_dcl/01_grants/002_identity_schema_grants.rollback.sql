REVOKE USAGE ON SCHEMA identity_and_access FROM identity_reader, identity_writer;
REVOKE EXECUTE ON FUNCTION identity_and_access.supersede_unused_password_reset_tokens()
    FROM identity_writer;
GRANT EXECUTE ON FUNCTION identity_and_access.supersede_unused_password_reset_tokens()
    TO PUBLIC;
-- Existing table/sequence grants predate this release and survive SET SCHEMA.
