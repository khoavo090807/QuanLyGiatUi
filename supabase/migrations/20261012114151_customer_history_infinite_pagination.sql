CREATE OR REPLACE FUNCTION public.get_customer_history_page(
  p_status text,
  p_offset integer DEFAULT 0,
  p_limit integer DEFAULT 20
)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
  WITH history_rows AS (
    SELECT
      'order'::text AS source,
      order_row."DonHangID"::bigint AS record_id,
      order_row."NgayTao" AS created_at,
      CASE
        WHEN order_row."TrangThai" = 'Đã hủy' THEN 'cancelled'
        WHEN order_row."TrangThai" IN ('Đã giao', 'Đã thanh toán', 'Hoàn thành')
          THEN 'completed'
        ELSE 'processing'
      END AS status_group
    FROM public."DonHang" AS order_row

    UNION ALL

    SELECT
      'booking'::text AS source,
      booking_row."BookingID"::bigint AS record_id,
      booking_row."NgayTao" AS created_at,
      CASE
        WHEN booking_row."TrangThai" IN ('DaHuy', 'Đã hủy') THEN 'cancelled'
        WHEN booking_row."TrangThai" IN ('HoanThanh', 'DaGiao', 'Hoàn thành', 'Đã giao')
          THEN 'completed'
        ELSE 'processing'
      END AS status_group
    FROM public."Booking" AS booking_row
    WHERE NOT EXISTS (
      SELECT 1
      FROM public."DonHang" AS linked_order
      WHERE linked_order."BookingID" = booking_row."BookingID"
    )
  ),
  filtered_rows AS (
    SELECT source, record_id, created_at
    FROM history_rows
    WHERE status_group = p_status
  ),
  page_rows AS (
    SELECT source, record_id, created_at
    FROM filtered_rows
    ORDER BY created_at DESC, source, record_id DESC
    OFFSET greatest(coalesce(p_offset, 0), 0)
    LIMIT greatest(1, least(coalesce(p_limit, 20), 100))
  )
  SELECT jsonb_build_object(
    'total_count', (SELECT count(*) FROM filtered_rows),
    'items', coalesce(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'source', page.source,
            'record_id', page.record_id
          )
          ORDER BY page.created_at DESC, page.source, page.record_id DESC
        )
        FROM page_rows AS page
      ),
      '[]'::jsonb
    )
  );
$$;

REVOKE ALL ON FUNCTION public.get_customer_history_page(text, integer, integer)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_customer_history_page(text, integer, integer)
  TO authenticated;
