-- ========================================
-- Member access controls by department/folder
-- ========================================

CREATE TABLE IF NOT EXISTS public.project_member_access (
  project_id uuid NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  department_ids uuid[] NOT NULL DEFAULT '{}',
  folder_ids uuid[] NOT NULL DEFAULT '{}',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (project_id, user_id)
);

DROP TRIGGER IF EXISTS handle_project_member_access_updated_at ON public.project_member_access;
CREATE TRIGGER handle_project_member_access_updated_at
  BEFORE UPDATE ON public.project_member_access
  FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

ALTER TABLE public.project_member_access ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Members can view access settings of project" ON public.project_member_access;
CREATE POLICY "Members can view access settings of project"
  ON public.project_member_access FOR SELECT
  USING (
    EXISTS (
      SELECT 1
      FROM public.project_members pm
      WHERE pm.project_id = project_member_access.project_id
        AND pm.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Owner admin can manage access settings" ON public.project_member_access;
CREATE POLICY "Owner admin can manage access settings"
  ON public.project_member_access FOR ALL
  USING (
    EXISTS (
      SELECT 1
      FROM public.project_members pm
      WHERE pm.project_id = project_member_access.project_id
        AND pm.user_id = auth.uid()
        AND pm.role IN ('owner', 'admin')
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.project_members pm
      WHERE pm.project_id = project_member_access.project_id
        AND pm.user_id = auth.uid()
        AND pm.role IN ('owner', 'admin')
    )
  );

