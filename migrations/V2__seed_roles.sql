-- ============================================================
-- Identity & Access
-- V2 - Insert required system roles
-- ============================================================

INSERT INTO roles (name)
VALUES
    ('PACIENTE'),
    ('PROFESIONAL'),
    ('ADMIN')
ON CONFLICT (name) DO NOTHING;