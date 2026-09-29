-- Record when a password reset token is superseded by a newer token.
-- A superseded token is terminal and therefore must also be marked as used.
--
-- The constraint is added as NOT VALID so existing rows are not scanned
-- while the ALTER TABLE transaction holds its strongest lock.
-- Validation is performed by the following changeset in a separate
-- transaction.

ALTER TABLE password_reset_tokens
    ADD COLUMN superseded_at TIMESTAMPTZ;

ALTER TABLE password_reset_tokens
    ADD CONSTRAINT chk_password_reset_tokens_superseded_used
    CHECK (
        superseded_at IS NULL
        OR used = TRUE
    )
    NOT VALID;