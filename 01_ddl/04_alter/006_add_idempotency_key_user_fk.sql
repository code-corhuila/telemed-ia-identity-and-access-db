ALTER TABLE identity_idempotency_key
    ADD CONSTRAINT fk_identity_idempotency_key_user
        FOREIGN KEY (user_id)
        REFERENCES users(id)
        ON DELETE RESTRICT;
