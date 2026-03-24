-- ========================================
-- Migrate video calls from board-level to project-level
-- ========================================

-- 1) Add project_id to rooms
ALTER TABLE public.video_call_rooms
  ADD COLUMN IF NOT EXISTS project_id UUID REFERENCES public.projects(id) ON DELETE CASCADE;

-- 2) Backfill project_id from board_id
UPDATE public.video_call_rooms r
SET project_id = b.project_id
FROM public.boards b
WHERE r.project_id IS NULL
  AND r.board_id = b.id;

-- 3) Ensure index and NOT NULL after backfill
CREATE INDEX IF NOT EXISTS idx_video_call_rooms_project_id
  ON public.video_call_rooms(project_id);

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'video_call_rooms'
      AND column_name = 'project_id'
      AND is_nullable = 'YES'
  ) THEN
    -- Safe to enforce when all rows are backfilled
    IF NOT EXISTS (
      SELECT 1
      FROM public.video_call_rooms
      WHERE project_id IS NULL
    ) THEN
      ALTER TABLE public.video_call_rooms
        ALTER COLUMN project_id SET NOT NULL;
    END IF;
  END IF;
END
$$;

-- 3.1) Make legacy board_id optional after migration
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'video_call_rooms'
      AND column_name = 'board_id'
      AND is_nullable = 'NO'
  ) THEN
    ALTER TABLE public.video_call_rooms
      ALTER COLUMN board_id DROP NOT NULL;
  END IF;
END
$$;

-- 4) RLS for rooms (project-level)
DROP POLICY IF EXISTS "Call room members can view rooms" ON public.video_call_rooms;
CREATE POLICY "Call room members can view rooms"
  ON public.video_call_rooms FOR SELECT
  USING (public.is_project_member_by_project(project_id));

DROP POLICY IF EXISTS "Call room members can create rooms" ON public.video_call_rooms;
CREATE POLICY "Call room members can create rooms"
  ON public.video_call_rooms FOR INSERT
  WITH CHECK (
    created_by = auth.uid()
    AND public.is_project_member_by_project(project_id)
  );

DROP POLICY IF EXISTS "Call room creator can delete rooms" ON public.video_call_rooms;
CREATE POLICY "Call room creator can delete rooms"
  ON public.video_call_rooms FOR DELETE
  USING (
    created_by = auth.uid()
    AND public.is_project_member_by_project(project_id)
  );

-- 5) RLS for participants (project-level via room.project_id)
DROP POLICY IF EXISTS "Call room members can view participants" ON public.video_call_participants;
CREATE POLICY "Call room members can view participants"
  ON public.video_call_participants FOR SELECT
  USING (
    EXISTS (
      SELECT 1
      FROM public.video_call_rooms r
      WHERE r.id = room_id
        AND public.is_project_member_by_project(r.project_id)
    )
  );

DROP POLICY IF EXISTS "Call room members can join" ON public.video_call_participants;
CREATE POLICY "Call room members can join"
  ON public.video_call_participants FOR INSERT
  WITH CHECK (
    user_id = auth.uid()
    AND EXISTS (
      SELECT 1
      FROM public.video_call_rooms r
      WHERE r.id = room_id
        AND public.is_project_member_by_project(r.project_id)
    )
  );

DROP POLICY IF EXISTS "Users can leave call rooms" ON public.video_call_participants;
CREATE POLICY "Users can leave call rooms"
  ON public.video_call_participants FOR DELETE
  USING (
    user_id = auth.uid()
    AND EXISTS (
      SELECT 1
      FROM public.video_call_rooms r
      WHERE r.id = room_id
        AND public.is_project_member_by_project(r.project_id)
    )
  );

-- 6) RLS for signals (project-level via room.project_id)
DROP POLICY IF EXISTS "Call room members can view signals" ON public.video_call_signals;
CREATE POLICY "Call room members can view signals"
  ON public.video_call_signals FOR SELECT
  USING (
    EXISTS (
      SELECT 1
      FROM public.video_call_rooms r
      WHERE r.id = room_id
        AND public.is_project_member_by_project(r.project_id)
    )
    AND target_id = auth.uid()
  );

DROP POLICY IF EXISTS "Call room members can insert signals" ON public.video_call_signals;
CREATE POLICY "Call room members can insert signals"
  ON public.video_call_signals FOR INSERT
  WITH CHECK (
    sender_id = auth.uid()
    AND EXISTS (
      SELECT 1
      FROM public.video_call_rooms r
      WHERE r.id = room_id
        AND public.is_project_member_by_project(r.project_id)
    )
  );
