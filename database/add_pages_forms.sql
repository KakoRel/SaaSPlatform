-- ========================================
-- Add project pages and forms (Jira-like tabs)
-- ========================================

CREATE TABLE IF NOT EXISTS public.project_pages (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  project_id UUID REFERENCES public.projects(id) ON DELETE CASCADE NOT NULL,
  title TEXT NOT NULL,
  content TEXT DEFAULT '' NOT NULL,
  created_by UUID REFERENCES public.users(id) ON DELETE SET NULL,
  updated_by UUID REFERENCES public.users(id) ON DELETE SET NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.project_forms (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  project_id UUID REFERENCES public.projects(id) ON DELETE CASCADE NOT NULL,
  title TEXT NOT NULL,
  description TEXT,
  fields JSONB DEFAULT '[]'::jsonb NOT NULL,
  issue_defaults JSONB DEFAULT '{}'::jsonb NOT NULL,
  is_active BOOLEAN DEFAULT TRUE NOT NULL,
  created_by UUID REFERENCES public.users(id) ON DELETE SET NULL,
  updated_by UUID REFERENCES public.users(id) ON DELETE SET NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.project_form_submissions (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  project_id UUID REFERENCES public.projects(id) ON DELETE CASCADE NOT NULL,
  form_id UUID REFERENCES public.project_forms(id) ON DELETE CASCADE NOT NULL,
  submitted_by UUID REFERENCES public.users(id) ON DELETE SET NULL,
  answers JSONB DEFAULT '{}'::jsonb NOT NULL,
  created_task_id UUID REFERENCES public.tasks(id) ON DELETE SET NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_project_pages_project_id
  ON public.project_pages(project_id);
CREATE INDEX IF NOT EXISTS idx_project_forms_project_id
  ON public.project_forms(project_id);
CREATE INDEX IF NOT EXISTS idx_project_form_submissions_project_id
  ON public.project_form_submissions(project_id);
CREATE INDEX IF NOT EXISTS idx_project_form_submissions_form_id
  ON public.project_form_submissions(form_id);

ALTER TABLE public.project_pages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.project_forms ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.project_form_submissions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Project members can view pages" ON public.project_pages;
CREATE POLICY "Project members can view pages"
  ON public.project_pages FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.project_members pm
      WHERE pm.project_id = project_pages.project_id
        AND pm.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Project members can insert pages" ON public.project_pages;
CREATE POLICY "Project members can insert pages"
  ON public.project_pages FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.project_members pm
      WHERE pm.project_id = project_pages.project_id
        AND pm.user_id = auth.uid()
        AND pm.role IN ('owner', 'admin', 'member')
    )
  );

DROP POLICY IF EXISTS "Project members can update pages" ON public.project_pages;
CREATE POLICY "Project members can update pages"
  ON public.project_pages FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.project_members pm
      WHERE pm.project_id = project_pages.project_id
        AND pm.user_id = auth.uid()
        AND pm.role IN ('owner', 'admin', 'member')
    )
  );

DROP POLICY IF EXISTS "Project admins can delete pages" ON public.project_pages;
CREATE POLICY "Project admins can delete pages"
  ON public.project_pages FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM public.project_members pm
      WHERE pm.project_id = project_pages.project_id
        AND pm.user_id = auth.uid()
        AND pm.role IN ('owner', 'admin')
    )
  );

DROP POLICY IF EXISTS "Project members can view forms" ON public.project_forms;
CREATE POLICY "Project members can view forms"
  ON public.project_forms FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.project_members pm
      WHERE pm.project_id = project_forms.project_id
        AND pm.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Project members can insert forms" ON public.project_forms;
CREATE POLICY "Project members can insert forms"
  ON public.project_forms FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.project_members pm
      WHERE pm.project_id = project_forms.project_id
        AND pm.user_id = auth.uid()
        AND pm.role IN ('owner', 'admin', 'member')
    )
  );

DROP POLICY IF EXISTS "Project members can update forms" ON public.project_forms;
CREATE POLICY "Project members can update forms"
  ON public.project_forms FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.project_members pm
      WHERE pm.project_id = project_forms.project_id
        AND pm.user_id = auth.uid()
        AND pm.role IN ('owner', 'admin', 'member')
    )
  );

DROP POLICY IF EXISTS "Project admins can delete forms" ON public.project_forms;
CREATE POLICY "Project admins can delete forms"
  ON public.project_forms FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM public.project_members pm
      WHERE pm.project_id = project_forms.project_id
        AND pm.user_id = auth.uid()
        AND pm.role IN ('owner', 'admin')
    )
  );

DROP POLICY IF EXISTS "Project members can view form submissions" ON public.project_form_submissions;
CREATE POLICY "Project members can view form submissions"
  ON public.project_form_submissions FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.project_members pm
      WHERE pm.project_id = project_form_submissions.project_id
        AND pm.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Project members can insert form submissions" ON public.project_form_submissions;
CREATE POLICY "Project members can insert form submissions"
  ON public.project_form_submissions FOR INSERT
  WITH CHECK (
    submitted_by = auth.uid()
    AND EXISTS (
      SELECT 1 FROM public.project_members pm
      WHERE pm.project_id = project_form_submissions.project_id
        AND pm.user_id = auth.uid()
        AND pm.role IN ('owner', 'admin', 'member')
    )
  );

DROP TRIGGER IF EXISTS handle_project_pages_updated_at ON public.project_pages;
CREATE TRIGGER handle_project_pages_updated_at
  BEFORE UPDATE ON public.project_pages
  FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

DROP TRIGGER IF EXISTS handle_project_forms_updated_at ON public.project_forms;
CREATE TRIGGER handle_project_forms_updated_at
  BEFORE UPDATE ON public.project_forms
  FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();
