-- identity-api accepts X-Correlation-Id values of up to 128 characters
-- (CorrelationIdFilter), so the outbox must store them without truncation.
ALTER TABLE identity_outbox_event
    ALTER COLUMN correlation_id TYPE VARCHAR(128);
