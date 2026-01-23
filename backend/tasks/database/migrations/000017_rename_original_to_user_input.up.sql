-- Rename original_title/description to user_input_title/description for clarity
-- These fields store the human-written input before AI cleanup
ALTER TABLE tasks RENAME COLUMN original_title TO user_input_title;
ALTER TABLE tasks RENAME COLUMN original_description TO user_input_description;
