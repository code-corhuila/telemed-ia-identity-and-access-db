-- identity_writer inherits SELECT through identity_reader. No DELETE:
-- a successful login resets the counters with UPDATE.
GRANT SELECT
ON TABLE login_attempts
TO identity_reader;

GRANT INSERT, UPDATE
ON TABLE login_attempts
TO identity_writer;
