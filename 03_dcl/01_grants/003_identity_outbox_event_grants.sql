-- identity_writer inherits SELECT through identity_reader. No DELETE:
-- published events are kept, with resetUrl already stripped.
GRANT SELECT
ON TABLE identity_outbox_event
TO identity_reader;

GRANT INSERT, UPDATE
ON TABLE identity_outbox_event
TO identity_writer;
