-- ========================================
-- SaaS Task Management Platform - Database Schema
-- ========================================

-- Enable necessary extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ========================================
-- ENUMS
-- ========================================

-- Task priorities
CREATE TYPE task_priority AS ENUM ('low', 'medium', 'high', 'urgent');

-- Task statuses
CREATE TYPE task_status AS ENUM ('todo', 'in_progress', 'review', 'done');

-- Project member roles
CREATE TYPE project_role AS ENUM ('owner', 'admin', 'member', 'viewer');

-- Notification types
CREATE TYPE notification_type AS ENUM ('task_assigned', 'task_updated', 'task_completed', 'deadline_reminder', 'project_invitation');

-- ========================================
-- TABLES
-- ========================================

-- Users table (extends auth.users)
CREATE TABLE public.users (
    id UUID REFERENCES auth.users(id) ON DELETE CASCADE PRIMARY KEY,
    email TEXT UNIQUE NOT NULL,
    full_name TEXT,
    avatar_url TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL
);

-- Projects table
CREATE TABLE public.projects (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    name TEXT NOT NULL,
    description TEXT,
    owner_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
    is_archived BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL
);

-- Project members table
CREATE TABLE public.project_members (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    project_id UUID REFERENCES public.projects(id) ON DELETE CASCADE NOT NULL,
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
    role project_role DEFAULT 'member' NOT NULL,
    joined_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    UNIQUE(project_id, user_id)
);

-- Tasks table
CREATE TABLE public.tasks (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    project_id UUID REFERENCES public.projects(id) ON DELETE CASCADE NOT NULL,
    title TEXT NOT NULL,
    description TEXT,
    assignee_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
    creator_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
    status task_status DEFAULT 'todo' NOT NULL,
    priority task_priority DEFAULT 'medium' NOT NULL,
    due_date TIMESTAMP WITH TIME ZONE,
    completed_at TIMESTAMP WITH TIME ZONE,
    position INTEGER DEFAULT 0, -- For Kanban board ordering
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL
);

-- Task comments table
CREATE TABLE public.task_comments (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    task_id UUID REFERENCES public.tasks(id) ON DELETE CASCADE NOT NULL,
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
    content TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL
);

-- User notification settings
CREATE TABLE public.notification_settings (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL UNIQUE,
    email_notifications BOOLEAN DEFAULT TRUE,
    task_assigned BOOLEAN DEFAULT TRUE,
    task_updated BOOLEAN DEFAULT TRUE,
    task_completed BOOLEAN DEFAULT TRUE,
    deadline_reminder BOOLEAN DEFAULT TRUE,
    project_invitation BOOLEAN DEFAULT TRUE,
    reminder_hours_before INTEGER DEFAULT 24,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL
);

-- Notifications table
CREATE TABLE public.notifications (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
    type notification_type NOT NULL,
    title TEXT NOT NULL,
    message TEXT NOT NULL,
    data JSONB, -- Additional data (task_id, project_id, etc.)
    is_read BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL
);

-- ========================================
-- INDEXES
-- ========================================

-- Users indexes
CREATE INDEX idx_users_email ON public.users(email);

-- Projects indexes
CREATE INDEX idx_projects_owner_id ON public.projects(owner_id);
CREATE INDEX idx_projects_is_archived ON public.projects(is_archived);

-- Project members indexes
CREATE INDEX idx_project_members_project_id ON public.project_members(project_id);
CREATE INDEX idx_project_members_user_id ON public.project_members(user_id);
CREATE INDEX idx_project_members_role ON public.project_members(role);

-- Tasks indexes
CREATE INDEX idx_tasks_project_id ON public.tasks(project_id);
CREATE INDEX idx_tasks_assignee_id ON public.tasks(assignee_id);
CREATE INDEX idx_tasks_creator_id ON public.tasks(creator_id);
CREATE INDEX idx_tasks_status ON public.tasks(status);
CREATE INDEX idx_tasks_priority ON public.tasks(priority);
CREATE INDEX idx_tasks_due_date ON public.tasks(due_date);
CREATE INDEX idx_tasks_position ON public.tasks(project_id, position);

-- Task comments indexes
CREATE INDEX idx_task_comments_task_id ON public.task_comments(task_id);
CREATE INDEX idx_task_comments_user_id ON public.task_comments(user_id);

-- Notifications indexes
CREATE INDEX idx_notifications_user_id ON public.notifications(user_id);
CREATE INDEX idx_notifications_is_read ON public.notifications(is_read);
CREATE INDEX idx_notifications_created_at ON public.notifications(created_at);

-- ========================================
-- FUNCTIONS AND TRIGGERS
-- ========================================

-- Function to update updated_at column
CREATE OR REPLACE FUNCTION public.handle_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Triggers for updated_at
CREATE TRIGGER handle_users_updated_at
    BEFORE UPDATE ON public.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

CREATE TRIGGER handle_projects_updated_at
    BEFORE UPDATE ON public.projects
    FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

CREATE TRIGGER handle_project_members_updated_at
    BEFORE UPDATE ON public.project_members
    FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

CREATE TRIGGER handle_tasks_updated_at
    BEFORE UPDATE ON public.tasks
    FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

CREATE TRIGGER handle_task_comments_updated_at
    BEFORE UPDATE ON public.task_comments
    FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

CREATE TRIGGER handle_notification_settings_updated_at
    BEFORE UPDATE ON public.notification_settings
    FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

-- Function to create user profile after auth signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.users (id, email, full_name)
    VALUES (
        NEW.id,
        NEW.email,
        COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.email)
    );
    
    -- Create default notification settings
    INSERT INTO public.notification_settings (user_id)
    VALUES (NEW.id);
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger to create user profile after signup
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Function to set completed_at when task status changes to 'done'
CREATE OR REPLACE FUNCTION public.handle_task_completion()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.status = 'done' AND OLD.status != 'done' THEN
        NEW.completed_at = NOW();
    ELSIF NEW.status != 'done' AND OLD.status = 'done' THEN
        NEW.completed_at = NULL;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER handle_task_completion_trigger
    BEFORE UPDATE ON public.tasks
    FOR EACH ROW EXECUTE FUNCTION public.handle_task_completion();

-- ========================================
-- FUNCTIONS AND TRIGGERS
-- ========================================

-- Function to check project membership without recursion
CREATE OR REPLACE FUNCTION public.is_project_member(p_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM public.project_members
    WHERE project_id = p_id AND user_id = auth.uid()
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Enable RLS on all tables
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.projects ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.project_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tasks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.task_comments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notification_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

-- Users policies
CREATE POLICY "Users can view own profile"
    ON public.users FOR SELECT
    USING (auth.uid() = id);

CREATE POLICY "Users can update own profile"
    ON public.users FOR UPDATE
    USING (auth.uid() = id);

-- Projects policies
CREATE POLICY "Project members can view projects"
    ON public.projects FOR SELECT
    USING (public.is_project_member(id));

CREATE POLICY "Project owners can insert projects"
    ON public.projects FOR INSERT
    WITH CHECK (owner_id = auth.uid());

CREATE POLICY "Project owners and admins can update projects"
    ON public.projects FOR UPDATE
    USING (
        owner_id = auth.uid()
        OR EXISTS (
            SELECT 1 FROM public.project_members
            WHERE project_members.project_id = projects.id
            AND project_members.user_id = auth.uid()
            AND project_members.role IN ('owner', 'admin')
        )
    );

CREATE POLICY "Project owners can delete projects"
    ON public.projects FOR DELETE
    USING (owner_id = auth.uid());

-- Project members policies
CREATE POLICY "Project members can view project members"
    ON public.project_members FOR SELECT
    USING (public.is_project_member(project_id));

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

CREATE POLICY "Project owners and admins can update project members"
    ON public.project_members FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM public.project_members pm
            WHERE pm.project_id = project_members.project_id
            AND pm.user_id = auth.uid()
            AND pm.role IN ('owner', 'admin')
        )
    );

CREATE POLICY "Project owners and admins can delete project members"
    ON public.project_members FOR DELETE
    USING (
        EXISTS (
            SELECT 1 FROM public.project_members pm
            WHERE pm.project_id = project_members.project_id
            AND pm.user_id = auth.uid()
            AND pm.role IN ('owner', 'admin')
        )
        OR user_id = auth.uid() -- Users can leave projects
    );

-- Tasks policies
CREATE POLICY "Project members can view tasks"
    ON public.tasks FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.project_members
            WHERE project_members.project_id = tasks.project_id
            AND project_members.user_id = auth.uid()
        )
    );

CREATE POLICY "Project members can insert tasks"
    ON public.tasks FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.project_members
            WHERE project_members.project_id = tasks.project_id
            AND project_members.user_id = auth.uid()
            AND project_members.role IN ('owner', 'admin', 'member')
        )
    );

CREATE POLICY "Task assignees and project members can update tasks"
    ON public.tasks FOR UPDATE
    USING (
        assignee_id = auth.uid()
        OR creator_id = auth.uid()
        OR EXISTS (
            SELECT 1 FROM public.project_members
            WHERE project_members.project_id = tasks.project_id
            AND project_members.user_id = auth.uid()
            AND project_members.role IN ('owner', 'admin', 'member')
        )
    );

CREATE POLICY "Project owners and admins can delete tasks"
    ON public.tasks FOR DELETE
    USING (
        creator_id = auth.uid()
        OR EXISTS (
            SELECT 1 FROM public.project_members
            WHERE project_members.project_id = tasks.project_id
            AND project_members.user_id = auth.uid()
            AND project_members.role IN ('owner', 'admin')
        )
    );

-- Task comments policies
CREATE POLICY "Project members can view task comments"
    ON public.task_comments FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.project_members
            WHERE project_members.project_id = (
                SELECT project_id FROM public.tasks
                WHERE tasks.id = task_comments.task_id
            )
            AND project_members.user_id = auth.uid()
        )
    );

CREATE POLICY "Project members can insert task comments"
    ON public.task_comments FOR INSERT
    WITH CHECK (
        user_id = auth.uid()
        AND EXISTS (
            SELECT 1 FROM public.project_members
            WHERE project_members.project_id = (
                SELECT project_id FROM public.tasks
                WHERE tasks.id = task_comments.task_id
            )
            AND project_members.user_id = auth.uid()
        )
    );

CREATE POLICY "Comment authors can update own comments"
    ON public.task_comments FOR UPDATE
    USING (user_id = auth.uid());

CREATE POLICY "Comment authors and project admins can delete comments"
    ON public.task_comments FOR DELETE
    USING (
        user_id = auth.uid()
        OR EXISTS (
            SELECT 1 FROM public.project_members
            WHERE project_members.project_id = (
                SELECT project_id FROM public.tasks
                WHERE tasks.id = task_comments.task_id
            )
            AND project_members.user_id = auth.uid()
            AND project_members.role IN ('owner', 'admin')
        )
    );

-- Notification settings policies
CREATE POLICY "Users can view own notification settings"
    ON public.notification_settings FOR SELECT
    USING (user_id = auth.uid());

CREATE POLICY "Users can update own notification settings"
    ON public.notification_settings FOR UPDATE
    USING (user_id = auth.uid());

CREATE POLICY "Users can insert own notification settings"
    ON public.notification_settings FOR INSERT
    WITH CHECK (user_id = auth.uid());

-- Notifications policies
CREATE POLICY "Users can view own notifications"
    ON public.notifications FOR SELECT
    USING (user_id = auth.uid());

CREATE POLICY "Users can update own notifications"
    ON public.notifications FOR UPDATE
    USING (user_id = auth.uid());

CREATE POLICY "System can insert notifications"
    ON public.notifications FOR INSERT
    WITH CHECK (true); -- Only service role can insert

-- ========================================
-- VIEWS FOR COMMON QUERIES
-- ========================================

-- View for user projects with member info
CREATE OR REPLACE VIEW public.user_projects AS
SELECT 
    p.*,
    pm.role,
    pm.joined_at as member_since,
    u.full_name as owner_name,
    u.email as owner_email
FROM public.projects p
JOIN public.project_members pm ON p.id = pm.project_id
JOIN public.users u ON p.owner_id = u.id
WHERE pm.user_id = auth.uid();

-- View for tasks with assignee and creator info
CREATE OR REPLACE VIEW public.project_tasks AS
SELECT 
    t.*,
    assignee.full_name as assignee_name,
    assignee.email as assignee_email,
    creator.full_name as creator_name,
    creator.email as creator_email
FROM public.tasks t
LEFT JOIN public.users assignee ON t.assignee_id = assignee.id
LEFT JOIN public.users creator ON t.creator_id = creator.id
WHERE EXISTS (
    SELECT 1 FROM public.project_members pm
    WHERE pm.project_id = t.project_id
    AND pm.user_id = auth.uid()
);

-- ========================================
-- REALTIME SUBSCRIPTIONS
-- ========================================

-- Enable realtime for tables that need live updates
ALTER PUBLICATION supabase_realtime ADD TABLE public.projects;
ALTER PUBLICATION supabase_realtime ADD TABLE public.tasks;
ALTER PUBLICATION supabase_realtime ADD TABLE public.project_members;
ALTER PUBLICATION supabase_realtime ADD TABLE public.task_comments;

-- ========================================
-- SAMPLE DATA (Optional - for development)
-- ========================================

-- You can uncomment this section for development/testing
/*
-- Insert sample project (run this manually after creating first user)
-- INSERT INTO public.projects (name, description, owner_id)
-- VALUES ('Demo Project', 'A sample project for testing', 'YOUR_USER_ID_HERE');
*/
