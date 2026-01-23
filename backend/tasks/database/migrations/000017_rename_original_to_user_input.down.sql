-- Revert: rename user_input_title/description back to original_title/description
ALTER TABLE tasks RENAME COLUMN user_input_title TO original_title;
ALTER TABLE tasks RENAME COLUMN user_input_description TO original_description;
