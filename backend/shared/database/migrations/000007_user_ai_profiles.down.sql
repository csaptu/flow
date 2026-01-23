-- Remove system first context from ai_prompt_configs
DELETE FROM ai_prompt_configs WHERE key = 'system_first_context';

-- Drop user_ai_profiles table
DROP TABLE IF EXISTS user_ai_profiles;
