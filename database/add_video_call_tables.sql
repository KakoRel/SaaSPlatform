-- ========================================
-- Video Call Rooms (per board) + Signaling
-- ========================================

-- Helper: check if current user is a member of the board's project
CREATE OR REPLACE FUNCTION public.is_board_member_by_board(p_board_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1
    FROM public.boards b
    JOIN public.project_members pm
      ON pm.project_id = b.project_id
    WHERE b.id = p_board_id
      AND pm.user_id = auth.uid()
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.is_board_member_by_board(uuid) TO authenticated;

-- 1) Rooms
CREATE TABLE IF NOT EXISTS public.video_call_rooms (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  board_id UUID NOT NULL REFERENCES public.boards(id) ON DELETE CASCADE,
  created_by UUID REFERENCES public.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
  updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

-- 2) Participants
CREATE TABLE IF NOT EXISTS public.video_call_participants (
  room_id UUID NOT NULL REFERENCES public.video_call_rooms(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  display_name TEXT NOT NULL,
  joined_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
  left_at TIMESTAMPTZ,
  PRIMARY KEY (room_id, user_id)
);

-- 3) Signals (offer/answer/ice)
CREATE TABLE IF NOT EXISTS public.video_call_signals (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  room_id UUID NOT NULL REFERENCES public.video_call_rooms(id) ON DELETE CASCADE,
  sender_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  target_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  signal_type TEXT NOT NULL CHECK (signal_type IN ('offer', 'answer', 'ice')),
  payload JSONB NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_video_call_rooms_board_id ON public.video_call_rooms(board_id);
CREATE INDEX IF NOT EXISTS idx_video_call_participants_room_id ON public.video_call_participants(room_id);
CREATE INDEX IF NOT EXISTS idx_video_call_signals_room_target
  ON public.video_call_signals(room_id, target_id, created_at);

-- Keep updated_at in sync
DROP TRIGGER IF EXISTS handle_video_call_rooms_updated_at ON public.video_call_rooms;
CREATE TRIGGER handle_video_call_rooms_updated_at
  BEFORE UPDATE ON public.video_call_rooms
  FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

-- Enable RLS
ALTER TABLE public.video_call_rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.video_call_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.video_call_signals ENABLE ROW LEVEL SECURITY;

-- =========================
-- RLS: video_call_rooms
-- =========================
DROP POLICY IF EXISTS "Call room members can view rooms" ON public.video_call_rooms;
CREATE POLICY "Call room members can view rooms"
  ON public.video_call_rooms FOR SELECT
  USING (public.is_board_member_by_board(board_id));

DROP POLICY IF EXISTS "Call room members can create rooms" ON public.video_call_rooms;
CREATE POLICY "Call room members can create rooms"
  ON public.video_call_rooms FOR INSERT
  WITH CHECK (
    created_by = auth.uid()
    AND public.is_board_member_by_board(board_id)
  );

DROP POLICY IF EXISTS "Call room creator can delete rooms" ON public.video_call_rooms;
CREATE POLICY "Call room creator can delete rooms"
  ON public.video_call_rooms FOR DELETE
  USING (created_by = auth.uid());

-- =========================
-- RLS: participants
-- =========================
DROP POLICY IF EXISTS "Call room members can view participants" ON public.video_call_participants;
CREATE POLICY "Call room members can view participants"
  ON public.video_call_participants FOR SELECT
  USING (
    EXISTS (
      SELECT 1
      FROM public.video_call_rooms r
      WHERE r.id = room_id
        AND public.is_board_member_by_board(r.board_id)
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
        AND public.is_board_member_by_board(r.board_id)
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
        AND public.is_board_member_by_board(r.board_id)
    )
  );

-- =========================
-- RLS: signals
-- =========================
DROP POLICY IF EXISTS "Call room members can view signals" ON public.video_call_signals;
CREATE POLICY "Call room members can view signals"
  ON public.video_call_signals FOR SELECT
  USING (
    EXISTS (
      SELECT 1
      FROM public.video_call_rooms r
      WHERE r.id = room_id
        AND public.is_board_member_by_board(r.board_id)
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
        AND public.is_board_member_by_board(r.board_id)
    )
  );

