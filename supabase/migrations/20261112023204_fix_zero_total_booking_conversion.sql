BEGIN;

CREATE OR REPLACE FUNCTION private.copy_booking_delivery_fee_to_order()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  pickup_fee numeric(12, 2);
  delivery_fee numeric(12, 2);
BEGIN
  IF NEW."BookingID" IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT "PickupDeliveryFee", "DeliveryFee"
  INTO pickup_fee, delivery_fee
  FROM public."Booking"
  WHERE "BookingID" = NEW."BookingID";

  IF FOUND THEN
    NEW."PhiGiaoHang" := coalesce(pickup_fee, 0) + coalesce(delivery_fee, 0);
    NEW."ThanhTien" := greatest(
      NEW."TongTien" + NEW."PhiGiaoHang"
        - least(
          NEW."TongTien",
          greatest(NEW."TienGiamKhuyenMai", 0)
        )
        - greatest(NEW."TienGiamDoDiem", 0),
      0
    );
  END IF;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION private.copy_booking_delivery_fee_to_order()
  FROM PUBLIC, anon, authenticated, service_role;

COMMIT;
