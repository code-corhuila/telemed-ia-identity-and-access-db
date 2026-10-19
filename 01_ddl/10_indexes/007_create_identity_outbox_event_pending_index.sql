CREATE INDEX ix_identity_outbox_event_pending
    ON identity_outbox_event(occurred_at)
    WHERE published_at IS NULL;
