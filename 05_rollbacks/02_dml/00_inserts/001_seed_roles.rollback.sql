DELETE FROM roles r
WHERE r.name IN ('PATIENT', 'PROFESSIONAL', 'ADMIN')
  AND NOT EXISTS (
      SELECT 1
      FROM users u
      WHERE u.role_id = r.id
  );