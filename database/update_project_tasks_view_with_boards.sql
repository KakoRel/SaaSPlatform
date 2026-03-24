-- ========================================
-- Update `project_tasks` view to include `board_id`
-- ========================================
-- Run this on Supabase SQL editor for existing projects.

DROP VIEW IF EXISTS public.project_tasks;

CREATE VIEW public.project_tasks (
  id,
  project_id,
  board_id,
  sprint_id,
  issue_type,
  epic_id,
  title,
  description,
  assignee_id,
  creator_id,
  status,
  priority,
  due_date,
  completed_at,
  position,
  image_url,
  created_at,
  updated_at,
  assignee_name,
  assignee_email,
  creator_name,
  creator_email
)
AS
SELECT
  t.id,
  t.project_id,
  t.board_id,
  t.sprint_id,
  t.issue_type,
  t.epic_id,
  t.title,
  t.description,
  t.assignee_id,
  t.creator_id,
  t.status,
  t.priority,
  t.due_date,
  t.completed_at,
  t.position,
  t.image_url,
  t.created_at,
  t.updated_at,
  assignee.full_name AS assignee_name,
  assignee.email AS assignee_email,
  creator.full_name AS creator_name,
  creator.email AS creator_email
FROM public.tasks t
LEFT JOIN public.users assignee ON t.assignee_id = assignee.id
LEFT JOIN public.users creator ON t.creator_id = creator.id
WHERE EXISTS (
  SELECT 1
  FROM public.project_members pm
  WHERE pm.project_id = t.project_id
    AND pm.user_id = auth.uid()
);

