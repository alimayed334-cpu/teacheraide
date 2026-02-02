-- add_missing_columns.sql
BEGIN TRANSACTION;

-- التحقق من وجود الأعمدة المفقودة وإضافتها إذا لزم الأمر
ALTER TABLE students ADD COLUMN IF NOT EXISTS cheating_count INTEGER DEFAULT 0;
ALTER TABLE students ADD COLUMN IF NOT EXISTS missing_count INTEGER DEFAULT 0;

COMMIT;
