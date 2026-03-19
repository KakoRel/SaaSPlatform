-- ==========================================
-- FIX FOR RLS INFINITE RECURSION
-- ==========================================

-- 1. Create a helper function to check membership without recursion.
-- Security definer bypasses RLS for the table it queries internally.
CREATE OR REPLACE FUNCTION public.is_project_member(p_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM public.project_members
    WHERE project_id = p_id AND user_id = auth.uid()
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 2. Update policies for public.project_members
DROP POLICY IF EXISTS "Project members can view project members" ON public.project_members;
CREATE POLICY "Project members can view project members"
    ON public.project_members FOR SELECT
    USING (public.is_project_member(project_id));

DROP POLICY IF EXISTS "Project owners and admins can insert project members" ON public.project_members;
CREATE POLICY "Project owners and admins can insert project members"
    ON public.project_members FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.project_members pm
            WHERE pm.project_id = project_members.project_id
            AND pm.user_id = auth.uid()
            AND pm.role IN ('owner', 'admin')
        )
    );
-- Note: INSERT/UPDATE/DELETE are usually less recursive than SELECT because they often check the state *before* the change.
-- However, we can use the function there too if needed.

-- 3. Update policies for public.projects (to avoid cross-table recursion)
DROP POLICY IF EXISTS "Project members can view projects" ON public.projects;
CREATE POLICY "Project members can view projects"
    ON public.projects FOR SELECT
    USING (public.is_project_member(id));
