-- A new schema is intentionally required; do not adopt an unknown owner/schema.
CREATE SCHEMA identity_and_access;
REVOKE ALL ON SCHEMA identity_and_access FROM PUBLIC;
