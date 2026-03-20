-- ========================================
-- Photo Attachments for Tasks
-- ========================================

-- 1. Add image_url to tasks table
ALTER TABLE public.tasks ADD COLUMN IF NOT EXISTS image_url TEXT;

-- 2. Create a storage bucket for task attachments
INSERT INTO storage.buckets (id, name, public) 
VALUES ('task-attachments', 'task-attachments', true)
ON CONFLICT (id) DO NOTHING;

-- 3. Set up Storage Policies for the new bucket
-- Allow anyone to read (public bucket)
CREATE POLICY "Public Access" ON storage.objects
  FOR SELECT USING (bucket_id = 'task-attachments');

-- Allow authenticated users to upload
CREATE POLICY "Authenticated users can upload task attachments" ON storage.objects
  FOR INSERT WITH CHECK (
    bucket_id = 'task-attachments' 
    AND auth.role() = 'authenticated'
  );

-- Allow owners to delete their own attachments (optional, for cleanup)
CREATE POLICY "Users can delete their own task attachments" ON storage.objects
  FOR DELETE USING (
    bucket_id = 'task-attachments' 
    AND auth.uid() = owner
  );
