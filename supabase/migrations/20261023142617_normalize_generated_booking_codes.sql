BEGIN;

CREATE OR REPLACE FUNCTION public.normalize_generated_booking_code()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO ''
AS $function$
BEGIN
  IF NEW."MaBooking" LIKE 'BK-%' THEN
    NEW."MaBooking" := 'BK' || lpad(
      NEW."BookingID"::text,
      greatest(4, length(NEW."BookingID"::text)),
      '0'
    );
  END IF;

  RETURN NEW;
END;
$function$;

CREATE TRIGGER booking_code_format_before_insert
BEFORE INSERT ON public."Booking"
FOR EACH ROW
WHEN (NEW."MaBooking" LIKE 'BK-%')
EXECUTE FUNCTION public.normalize_generated_booking_code();

COMMIT;
