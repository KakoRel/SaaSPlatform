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
CREATE POLICY "Users can view projects they are members of"
    ON public.projects FOR SELECT
    USING (
        owner_id = auth.uid() 
        OR public.is_project_member(id)
    );

-- 4. Ensure RLS is enabled
ALTER TABLE public.projects ENABLE ROW LEVEL SECURITY;
