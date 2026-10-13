-- Let customer screens receive payment/invoice/order settlement updates in realtime.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'ThanhToan'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public."ThanhToan";
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'HoaDon'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public."HoaDon";
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'DonHang'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public."DonHang";
  END IF;
END;
$$;
