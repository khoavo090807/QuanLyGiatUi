-- One authoritative cross-client notification contract.
-- Notifications are produced by business transactions/triggers, never by a
-- client insert.  This prevents a booking submitted from Flutter from being
-- duplicated when the database trigger also publishes the same event.
BEGIN;

REVOKE EXECUTE ON FUNCTION public.notify_staff_new_booking(bigint, text, text)
  FROM PUBLIC, anon, authenticated;

REVOKE INSERT, DELETE ON TABLE public."ThongBao" FROM anon, authenticated;
REVOKE INSERT, DELETE ON TABLE public.thongbao FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.mark_notifications_read(
  p_notification_ids bigint[] DEFAULT NULL
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  current_account_id bigint := (SELECT private.current_account_id());
  updated_count integer;
BEGIN
  IF (SELECT auth.uid()) IS NULL OR current_account_id IS NULL THEN
    RAISE EXCEPTION 'An active account is required';
  END IF;

  UPDATE public."ThongBao"
  SET "DaDoc" = true
  WHERE "TaiKhoanID" = current_account_id
    AND "DaDoc" = false
    AND (
      p_notification_ids IS NULL
      OR "ThongBaoID" = ANY (p_notification_ids)
    );

  GET DIAGNOSTICS updated_count = ROW_COUNT;
  RETURN updated_count;
END;
$$;

REVOKE ALL ON FUNCTION public.mark_notifications_read(bigint[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mark_notifications_read(bigint[]) TO authenticated;

-- Keep the externally visible business state machine in one place.  Values
-- are deliberately the existing persisted values so Laravel and Flutter do
-- not have to translate status labels before calling the RPC.
COMMENT ON FUNCTION public.transition_laundry_order(bigint, text, text) IS
  'Staff-only order state transition: Chờ tiếp nhận -> Đã tiếp nhận -> Đang giặt -> Hoàn thành giặt -> Đang giao -> Đã giao; cancellation is allowed only before completion.';
COMMENT ON FUNCTION public.mark_notifications_read(bigint[]) IS
  'Marks only the authenticated account notifications as read; pass NULL to mark all unread notifications.';

COMMIT;
