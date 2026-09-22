-- ============================================================
-- Identity & Access
-- V2 - Insert required system roles
-- ============================================================

INSERT INTO roles (name)
VALUES
    ('PATIENT'),
    ('PROFESSIONAL'),
    ('ADMIN')
ON CONFLICT (name) DO NOTHING;