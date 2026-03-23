-- ========================================
-- RLS Fix: Automatic Project Membership
-- ========================================

-- 1. Create a function to automatically add the owner as a project member
CREATE OR REPLACE FUNCTION public.handle_new_project()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.project_members (project_id, user_id, role)
    VALUES (NEW.id, NEW.owner_id, 'owner');
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 2. Create the trigger
DROP TRIGGER IF EXISTS on_project_created ON public.projects;
CREATE TRIGGER on_project_created
    AFTER INSERT ON public.projects
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_project();

-- 3. Update Project Select Policy to be more robust
-- This ensures the owner can always see the project they just created,
-- even if there's any delay or issue with the membership record.
DROP POLICY IF EXISTS "Project members can view projects" ON public.projects;
DROP POLICY IF EXISTS "Users can view projects they are members of" ON public.projects;
CREATE POLICY "Users can view projects they are members of"
    ON public.projects FOR SELECT
    USING (
        owner_id = auth.uid() 
        OR public.is_project_member(id)
    );

-- 4. Ensure RLS is enabled
ALTER TABLE public.projects ENABLE ROW LEVEL SECURITY;

-- ========================================
-- Invite by email (RLS bypass helper)
-- ========================================
-- Public.users is protected by RLS (users can only see their own profile).
-- For project invitations we need a safe lookup by email.
-- This function:
-- - allows only project owners/admins of `p_project_id`
-- - looks up user id by email (case-insensitive)
-- - returns NULL if user is not found or access is denied

CREATE OR REPLACE FUNCTION public.find_user_id_by_email_for_project(
  p_project_id uuid,
  p_email text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $$
DECLARE
  v_user_id uuid;
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM public.project_members pm
    WHERE pm.project_id = p_project_id
      AND pm.user_id = auth.uid()
      AND pm.role IN ('owner', 'admin')
  ) THEN
    RETURN NULL;
  END IF;

  SELECT u.id INTO v_user_id
  FROM public.users u
  WHERE lower(u.email) = lower(p_email)
  LIMIT 1;

  RETURN v_user_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.find_user_id_by_email_for_project(uuid, text) TO authenticated;

-- ========================================
-- Project members can view other members
-- ========================================
-- Public.users RLS по умолчанию позволяет читать только свой профиль.
-- Для экрана участников нам нужно разрешить чтение профилей пользователей,
-- которые состоят в хотя бы одном общем проекте с текущим пользователем.

DROP POLICY IF EXISTS "Project members can view users in same projects" ON public.users;

CREATE POLICY "Project members can view users in same projects"
  ON public.users FOR SELECT
  USING (
    EXISTS (
      SELECT 1
      FROM public.project_members pm_me
      JOIN public.project_members pm_other
        ON pm_other.project_id = pm_me.project_id
      WHERE pm_me.user_id = auth.uid()
        AND pm_other.user_id = users.id
    )
  );

-- ========================================
-- Display user name by task + user (RLS-safe)
-- ========================================
-- Used by document editor to show `updated_by` as a name, not UUID.
CREATE OR REPLACE FUNCTION public.find_user_display_name_by_task_and_user(
  p_task_id uuid,
  p_user_id uuid
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $$
DECLARE
  v_project_id uuid;
  v_full_name text;
  v_email text;
BEGIN
  SELECT t.project_id INTO v_project_id
  FROM public.tasks t
  WHERE t.id = p_task_id
  LIMIT 1;

  IF v_project_id IS NULL THEN
    RETURN NULL;
  END IF;

  -- Only allow if current user is a project member of the task's project.
  IF NOT EXISTS (
    SELECT 1
    FROM public.project_members pm
    WHERE pm.project_id = v_project_id
      AND pm.user_id = auth.uid()
  ) THEN
    RETURN NULL;
  END IF;

  SELECT u.full_name, u.email
    INTO v_full_name, v_email
  FROM public.users u
  WHERE u.id = p_user_id
  LIMIT 1;

  RETURN COALESCE(NULLIF(v_full_name, ''), v_email);
END;
$$;

GRANT EXECUTE ON FUNCTION public.find_user_display_name_by_task_and_user(uuid, uuid) TO authenticated;
