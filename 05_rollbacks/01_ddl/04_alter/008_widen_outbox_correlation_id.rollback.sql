-- Fails if any stored correlation_id is longer than 64 characters; shorten
-- or clear those values before rolling back.
ALTER TABLE identity_outbox_event
    ALTER COLUMN correlation_id TYPE VARCHAR(64);
