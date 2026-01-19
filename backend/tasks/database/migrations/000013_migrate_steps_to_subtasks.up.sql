-- Migrate existing ai_steps to real subtasks (child tasks)
-- This converts the JSONB ai_steps array into actual task rows with parent_id

-- Create subtasks from ai_steps for each task that has them
DO $$
DECLARE
    task_record RECORD;
    step_element JSONB;
    step_index INT;
BEGIN
    -- Loop through all tasks that have ai_steps
    FOR task_record IN
        SELECT id, user_id, ai_steps
        FROM tasks
        WHERE ai_steps IS NOT NULL
          AND ai_steps != '[]'::jsonb
          AND deleted_at IS NULL
    LOOP
        step_index := 0;
        -- Loop through each step in ai_steps array
        FOR step_element IN
            SELECT jsonb_array_elements(task_record.ai_steps)
        LOOP
            -- Insert each step as a new child task
            INSERT INTO tasks (
                id,
                user_id,
                title,
                status,
                priority,
                tags,
                parent_id,
                depth,
                ai_steps,
                entities,
                version,
                created_at,
                updated_at
            ) VALUES (
                gen_random_uuid(),
                task_record.user_id,
                step_element->>'action',
                CASE WHEN (step_element->>'done')::boolean THEN 'completed'::task_status ELSE 'pending'::task_status END,
                0,  -- default priority
                ARRAY[]::text[],  -- empty tags array
                task_record.id,
                1,  -- depth = 1 (child of root)
                '[]'::jsonb,  -- empty ai_steps
                '[]'::jsonb,  -- empty entities
                1,
                NOW() + (step_index * interval '1 millisecond'),  -- Preserve order
                NOW()
            );
            step_index := step_index + 1;
        END LOOP;
    END LOOP;
END $$;

-- Clear the ai_steps column since data is now migrated
UPDATE tasks SET ai_steps = '[]'::jsonb WHERE ai_steps IS NOT NULL AND ai_steps != '[]'::jsonb;

-- Drop the ai_steps and ai_decomposed columns (no longer needed)
ALTER TABLE tasks DROP COLUMN IF EXISTS ai_steps;
ALTER TABLE tasks DROP COLUMN IF EXISTS ai_decomposed;
