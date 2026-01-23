-- Revert to original cleanup instructions

UPDATE ai_prompt_configs
SET value = 'Concise, action-oriented title (max 10 words)',
    updated_at = NOW()
WHERE key = 'clean_title_instruction';

UPDATE ai_prompt_configs
SET value = 'Brief summary if description is long (max 20 words)',
    updated_at = NOW()
WHERE key = 'summary_instruction';
