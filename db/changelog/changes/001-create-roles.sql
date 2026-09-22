-- ============================================================
-- Identity & Access
-- V1 - Create roles table
-- ============================================================

CREATE TABLE roles (
    id BIGSERIAL PRIMARY KEY,
    name VARCHAR(30) NOT NULL UNIQUE
);