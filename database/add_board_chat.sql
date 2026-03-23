-- ========================================
-- Board chat + unread tracking
-- ========================================

CREATE TABLE IF NOT EXISTS public.board_chat_messages (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  board_id UUID NOT NULL REFERENCES public.boards(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  message TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.board_chat_reads (
  board_id UUID NOT NULL REFERENCES public.boards(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  last_read_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (board_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_board_chat_messages_board_id
  ON public.board_chat_messages(board_id, created_at);

ALTER TABLE public.board_chat_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.board_chat_reads ENABLE ROW LEVEL SECURITY;

-- Read messages only for members of board project
DROP POLICY IF EXISTS "Board members can view board chat messages" ON public.board_chat_messages;
CREATE POLICY "Board members can view board chat messages"
  ON public.board_chat_messages FOR SELECT
  USING (public.is_board_member_by_board(board_id));

DROP POLICY IF EXISTS "Board members can send board chat messages" ON public.board_chat_messages;
CREATE POLICY "Board members can send board chat messages"
  ON public.board_chat_messages FOR INSERT
  WITH CHECK (
    user_id = auth.uid()
    AND public.is_board_member_by_board(board_id)
  );

DROP POLICY IF EXISTS "Board members can view own chat read state" ON public.board_chat_reads;
CREATE POLICY "Board members can view own chat read state"
  ON public.board_chat_reads FOR SELECT
  USING (
    user_id = auth.uid()
    AND public.is_board_member_by_board(board_id)
  );

DROP POLICY IF EXISTS "Board members can upsert own chat read state" ON public.board_chat_reads;
CREATE POLICY "Board members can upsert own chat read state"
  ON public.board_chat_reads FOR ALL
  USING (
    user_id = auth.uid()
    AND public.is_board_member_by_board(board_id)
  )
  WITH CHECK (
    user_id = auth.uid()
    AND public.is_board_member_by_board(board_id)
  );

