-- ========================================
-- Departments, folders, boards, documents, links, chats
-- ========================================

-- 1) Departments inside project
CREATE TABLE IF NOT EXISTS public.departments (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  project_id UUID REFERENCES public.projects(id) ON DELETE CASCADE NOT NULL,
  name TEXT NOT NULL,
  created_by UUID REFERENCES public.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
  updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
  UNIQUE(project_id, name)
);

-- 2) Folders inside department/project
CREATE TABLE IF NOT EXISTS public.project_folders (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  project_id UUID REFERENCES public.projects(id) ON DELETE CASCADE NOT NULL,
  department_id UUID REFERENCES public.departments(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  created_by UUID REFERENCES public.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
  updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
  UNIQUE(project_id, department_id, name)
);

-- 3) Boards inside folder/department/project
CREATE TABLE IF NOT EXISTS public.boards (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  project_id UUID REFERENCES public.projects(id) ON DELETE CASCADE NOT NULL,
  department_id UUID REFERENCES public.departments(id) ON DELETE SET NULL,
  folder_id UUID REFERENCES public.project_folders(id) ON DELETE SET NULL,
  name TEXT NOT NULL,
  created_by UUID REFERENCES public.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
  updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
  UNIQUE(project_id, folder_id, name)
);

-- 4) Tasks now may belong to a board
ALTER TABLE public.tasks
  ADD COLUMN IF NOT EXISTS board_id UUID REFERENCES public.boards(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_tasks_board_id ON public.tasks(board_id);

-- 5) Task links
CREATE TABLE IF NOT EXISTS public.task_links (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  task_id UUID REFERENCES public.tasks(id) ON DELETE CASCADE NOT NULL,
  title TEXT,
  url TEXT NOT NULL,
  created_by UUID REFERENCES public.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_task_links_task_id ON public.task_links(task_id);

-- 6) Task documents (simple text editor model)
CREATE TABLE IF NOT EXISTS public.documents (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  task_id UUID REFERENCES public.tasks(id) ON DELETE CASCADE NOT NULL,
  title TEXT NOT NULL,
  content TEXT DEFAULT '',
  created_by UUID REFERENCES public.users(id) ON DELETE SET NULL,
  updated_by UUID REFERENCES public.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
  updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_documents_task_id ON public.documents(task_id);

-- 7) Department/global chats
CREATE TABLE IF NOT EXISTS public.department_chat_messages (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  project_id UUID REFERENCES public.projects(id) ON DELETE CASCADE NOT NULL,
  department_id UUID REFERENCES public.departments(id) ON DELETE CASCADE,
  user_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
  message TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_department_chat_messages_project_id
  ON public.department_chat_messages(project_id);
CREATE INDEX IF NOT EXISTS idx_department_chat_messages_department_id
  ON public.department_chat_messages(department_id);

-- Keep updated_at in sync
DROP TRIGGER IF EXISTS handle_departments_updated_at ON public.departments;
CREATE TRIGGER handle_departments_updated_at
  BEFORE UPDATE ON public.departments
  FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

DROP TRIGGER IF EXISTS handle_project_folders_updated_at ON public.project_folders;
CREATE TRIGGER handle_project_folders_updated_at
  BEFORE UPDATE ON public.project_folders
  FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

DROP TRIGGER IF EXISTS handle_boards_updated_at ON public.boards;
CREATE TRIGGER handle_boards_updated_at
  BEFORE UPDATE ON public.boards
  FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

DROP TRIGGER IF EXISTS handle_documents_updated_at ON public.documents;
CREATE TRIGGER handle_documents_updated_at
  BEFORE UPDATE ON public.documents
  FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

-- Enable RLS
ALTER TABLE public.departments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.project_folders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.boards ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.task_links ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.department_chat_messages ENABLE ROW LEVEL SECURITY;

-- RLS helper: membership check by project_id
CREATE OR REPLACE FUNCTION public.is_project_member_by_project(project_uuid UUID)
RETURNS BOOLEAN AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1
    FROM public.project_members pm
    WHERE pm.project_id = project_uuid
      AND pm.user_id = auth.uid()
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Departments policies
DROP POLICY IF EXISTS "Project members can view departments" ON public.departments;
CREATE POLICY "Project members can view departments"
  ON public.departments FOR SELECT
  USING (public.is_project_member_by_project(project_id));

DROP POLICY IF EXISTS "Project members can insert departments" ON public.departments;
CREATE POLICY "Project members can insert departments"
  ON public.departments FOR INSERT
  WITH CHECK (public.is_project_member_by_project(project_id));

DROP POLICY IF EXISTS "Project members can update departments" ON public.departments;
CREATE POLICY "Project members can update departments"
  ON public.departments FOR UPDATE
  USING (public.is_project_member_by_project(project_id));

DROP POLICY IF EXISTS "Project members can delete departments" ON public.departments;
CREATE POLICY "Project members can delete departments"
  ON public.departments FOR DELETE
  USING (public.is_project_member_by_project(project_id));

-- Folders policies
DROP POLICY IF EXISTS "Project members can view folders" ON public.project_folders;
CREATE POLICY "Project members can view folders"
  ON public.project_folders FOR SELECT
  USING (public.is_project_member_by_project(project_id));

DROP POLICY IF EXISTS "Project members can insert folders" ON public.project_folders;
CREATE POLICY "Project members can insert folders"
  ON public.project_folders FOR INSERT
  WITH CHECK (public.is_project_member_by_project(project_id));

DROP POLICY IF EXISTS "Project members can update folders" ON public.project_folders;
CREATE POLICY "Project members can update folders"
  ON public.project_folders FOR UPDATE
  USING (public.is_project_member_by_project(project_id));

DROP POLICY IF EXISTS "Project members can delete folders" ON public.project_folders;
CREATE POLICY "Project members can delete folders"
  ON public.project_folders FOR DELETE
  USING (public.is_project_member_by_project(project_id));

-- Boards policies
DROP POLICY IF EXISTS "Project members can view boards" ON public.boards;
CREATE POLICY "Project members can view boards"
  ON public.boards FOR SELECT
  USING (public.is_project_member_by_project(project_id));

DROP POLICY IF EXISTS "Project members can insert boards" ON public.boards;
CREATE POLICY "Project members can insert boards"
  ON public.boards FOR INSERT
  WITH CHECK (public.is_project_member_by_project(project_id));

DROP POLICY IF EXISTS "Project members can update boards" ON public.boards;
CREATE POLICY "Project members can update boards"
  ON public.boards FOR UPDATE
  USING (public.is_project_member_by_project(project_id));

DROP POLICY IF EXISTS "Project members can delete boards" ON public.boards;
CREATE POLICY "Project members can delete boards"
  ON public.boards FOR DELETE
  USING (public.is_project_member_by_project(project_id));

-- Task links policies (derive project through task)
DROP POLICY IF EXISTS "Project members can view task links" ON public.task_links;
CREATE POLICY "Project members can view task links"
  ON public.task_links FOR SELECT
  USING (
    EXISTS (
      SELECT 1
      FROM public.tasks t
      WHERE t.id = task_links.task_id
        AND public.is_project_member_by_project(t.project_id)
    )
  );

DROP POLICY IF EXISTS "Project members can insert task links" ON public.task_links;
CREATE POLICY "Project members can insert task links"
  ON public.task_links FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.tasks t
      WHERE t.id = task_links.task_id
        AND public.is_project_member_by_project(t.project_id)
    )
  );

DROP POLICY IF EXISTS "Project members can delete task links" ON public.task_links;
CREATE POLICY "Project members can delete task links"
  ON public.task_links FOR DELETE
  USING (
    EXISTS (
      SELECT 1
      FROM public.tasks t
      WHERE t.id = task_links.task_id
        AND public.is_project_member_by_project(t.project_id)
    )
  );

-- Documents policies
DROP POLICY IF EXISTS "Project members can view documents" ON public.documents;
CREATE POLICY "Project members can view documents"
  ON public.documents FOR SELECT
  USING (
    EXISTS (
      SELECT 1
      FROM public.tasks t
      WHERE t.id = documents.task_id
        AND public.is_project_member_by_project(t.project_id)
    )
  );

DROP POLICY IF EXISTS "Project members can insert documents" ON public.documents;
CREATE POLICY "Project members can insert documents"
  ON public.documents FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.tasks t
      WHERE t.id = documents.task_id
        AND public.is_project_member_by_project(t.project_id)
    )
  );

DROP POLICY IF EXISTS "Project members can update documents" ON public.documents;
CREATE POLICY "Project members can update documents"
  ON public.documents FOR UPDATE
  USING (
    EXISTS (
      SELECT 1
      FROM public.tasks t
      WHERE t.id = documents.task_id
        AND public.is_project_member_by_project(t.project_id)
    )
  );

DROP POLICY IF EXISTS "Project members can delete documents" ON public.documents;
CREATE POLICY "Project members can delete documents"
  ON public.documents FOR DELETE
  USING (
    EXISTS (
      SELECT 1
      FROM public.tasks t
      WHERE t.id = documents.task_id
        AND public.is_project_member_by_project(t.project_id)
    )
  );

-- Department chat policies
DROP POLICY IF EXISTS "Project members can view department chats" ON public.department_chat_messages;
CREATE POLICY "Project members can view department chats"
  ON public.department_chat_messages FOR SELECT
  USING (public.is_project_member_by_project(project_id));

DROP POLICY IF EXISTS "Project members can send department chats" ON public.department_chat_messages;
CREATE POLICY "Project members can send department chats"
  ON public.department_chat_messages FOR INSERT
  WITH CHECK (
    public.is_project_member_by_project(project_id)
    AND user_id = auth.uid()
  );

-- View for boards with folder/department names
CREATE OR REPLACE VIEW public.project_boards AS
SELECT
  b.id,
  b.project_id,
  b.department_id,
  d.name AS department_name,
  b.folder_id,
  f.name AS folder_name,
  b.name,
  b.created_by,
  b.created_at,
  b.updated_at
FROM public.boards b
LEFT JOIN public.departments d ON d.id = b.department_id
LEFT JOIN public.project_folders f ON f.id = b.folder_id;

