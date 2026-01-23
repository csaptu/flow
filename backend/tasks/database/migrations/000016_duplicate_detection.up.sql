-- Add duplicate detection fields to tasks
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS duplicate_of JSONB DEFAULT '[]';
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS duplicate_resolved BOOLEAN DEFAULT false;
