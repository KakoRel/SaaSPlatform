-- ========================================
-- Add Jira-like sprints and issue typing
-- ========================================

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'sprint_status') THEN
    CREATE TYPE public.sprint_status AS ENUM ('planned', 'active', 'completed');
  END IF;
END
$$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'task_issue_type') THEN
    CREATE TYPE public.task_issue_type AS ENUM ('epic', 'story', 'task', 'bug');
  END IF;
END
$$;

CREATE TABLE IF NOT EXISTS public.sprints (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  project_id UUID REFERENCES public.projects(id) ON DELETE CASCADE NOT NULL,
  name TEXT NOT NULL,
  start_date TIMESTAMP WITH TIME ZONE,
  end_date TIMESTAMP WITH TIME ZONE,
  is_active BOOLEAN DEFAULT FALSE NOT NULL,
  status public.sprint_status DEFAULT 'planned' NOT NULL,
  created_by UUID REFERENCES public.users(id) ON DELETE SET NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_sprints_project_id ON public.sprints(project_id);
CREATE INDEX IF NOT EXISTS idx_sprints_project_active ON public.sprints(project_id, is_active);

ALTER TABLE public.tasks
  ADD COLUMN IF NOT EXISTS sprint_id UUID REFERENCES public.sprints(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS issue_type public.task_issue_type DEFAULT 'task' NOT NULL,
  ADD COLUMN IF NOT EXISTS epic_id UUID REFERENCES public.tasks(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_tasks_sprint_id ON public.tasks(sprint_id);
CREATE INDEX IF NOT EXISTS idx_tasks_issue_type ON public.tasks(issue_type);
CREATE INDEX IF NOT EXISTS idx_tasks_epic_id ON public.tasks(epic_id);

ALTER TABLE public.sprints ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Project members can view sprints" ON public.sprints;
CREATE POLICY "Project members can view sprints"
  ON public.sprints FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.project_members
      WHERE project_members.project_id = sprints.project_id
        AND project_members.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Project members can insert sprints" ON public.sprints;
CREATE POLICY "Project members can insert sprints"
  ON public.sprints FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.project_members
      WHERE project_members.project_id = sprints.project_id
        AND project_members.user_id = auth.uid()
        AND project_members.role IN ('owner', 'admin', 'member')
    )
  );

DROP POLICY IF EXISTS "Project members can update sprints" ON public.sprints;
CREATE POLICY "Project members can update sprints"
  ON public.sprints FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.project_members
      WHERE project_members.project_id = sprints.project_id
        AND project_members.user_id = auth.uid()
        AND project_members.role IN ('owner', 'admin', 'member')
    )
  );

DROP POLICY IF EXISTS "Project owners and admins can delete sprints" ON public.sprints;
CREATE POLICY "Project owners and admins can delete sprints"
  ON public.sprints FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM public.project_members
      WHERE project_members.project_id = sprints.project_id
        AND project_members.user_id = auth.uid()
        AND project_members.role IN ('owner', 'admin')
    )
  );

DROP TRIGGER IF EXISTS handle_sprints_updated_at ON public.sprints;
CREATE TRIGGER handle_sprints_updated_at
  BEFORE UPDATE ON public.sprints
  FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

ALTER PUBLICATION supabase_realtime ADD TABLE public.sprints;

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
