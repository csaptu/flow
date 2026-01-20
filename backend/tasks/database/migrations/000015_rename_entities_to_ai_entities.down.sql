-- Revert: rename ai_entities back to entities
ALTER TABLE tasks RENAME COLUMN ai_entities TO entities;
