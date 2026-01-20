-- Rename entities column to ai_entities for clarity (AI-extracted entities)
ALTER TABLE tasks RENAME COLUMN entities TO ai_entities;
