BEGIN;

ALTER TABLE public."Booking" DISABLE TRIGGER notify_customer_booking_changed;

UPDATE public."Booking"
SET "MaBooking" = 'BK' || lpad(
  "BookingID"::text,
  greatest(4, length("BookingID"::text)),
  '0'
)
WHERE "MaBooking" LIKE 'BK-%';

ALTER TABLE public."Booking" ENABLE TRIGGER notify_customer_booking_changed;

UPDATE public."ThongBao" AS notification
SET "NoiDung" = regexp_replace(
  notification."NoiDung",
  'BK-[A-Za-z0-9]+(-[A-Za-z0-9]+)*',
  booking."MaBooking",
  'g'
)
FROM public."Booking" AS booking
WHERE notification."BookingID" = booking."BookingID"
  AND notification."NoiDung" ~ 'BK-[A-Za-z0-9]+(-[A-Za-z0-9]+)*';

COMMIT;
