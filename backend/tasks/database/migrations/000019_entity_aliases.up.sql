-- Entity aliases for merging entities without modifying task data
-- When "Nam" is merged into "Nam Tran", we create a link rather than updating all tasks
CREATE TABLE IF NOT EXISTS entity_aliases (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    entity_type VARCHAR(50) NOT NULL,  -- 'person', 'location', 'organization'
    alias_value VARCHAR(255) NOT NULL,  -- The value being merged (e.g., "Nam")
    canonical_value VARCHAR(255) NOT NULL,  -- The target value (e.g., "Nam Tran")
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),

    -- Each alias can only point to one canonical value per user
    UNIQUE(user_id, entity_type, alias_value)
);

-- Index for looking up aliases when resolving entities
CREATE INDEX idx_entity_aliases_lookup ON entity_aliases(user_id, entity_type, alias_value);

-- Index for finding all aliases of a canonical value
CREATE INDEX idx_entity_aliases_canonical ON entity_aliases(user_id, entity_type, canonical_value);
