-- Update AI cleanup instructions to preserve entities

UPDATE ai_prompt_configs
SET value = 'Concise, action-oriented title (max 10 words). IMPORTANT: Preserve all entities - dates, times, people names, places, organizations must NOT be removed or changed.',
    updated_at = NOW()
WHERE key = 'clean_title_instruction';

UPDATE ai_prompt_configs
SET value = 'Brief summary if description is long (max 20 words). IMPORTANT: Preserve all entities - dates, times, people names, places, organizations must NOT be removed or changed.',
    updated_at = NOW()
WHERE key = 'summary_instruction';
