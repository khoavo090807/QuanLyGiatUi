create or replace view public.service_public_reviews
with (security_barrier = true)
as
with order_services as (
    select distinct
        ct."DonHangID",
        dv."DichVuID",
        dv."TenDichVu"
    from public."ChiTietDonHang" as ct
    join public."DichVu" as dv
      on dv."DichVuID" = ct."DichVuID"
),
service_stats as (
    select
        os."DonHangID",
        count(*)::integer as service_count,
        array_agg(os."TenDichVu" order by os."TenDichVu") as service_names
    from order_services as os
    group by os."DonHangID"
)
select
    dg."DanhGiaID" as review_id,
    os."DichVuID" as service_id,
    os."TenDichVu" as service_name,
    dg."SoSao" as rating,
    dg."BinhLuan" as comment,
    dg.shop_response,
    dg."NgayDanhGia" as reviewed_at,
    stats.service_count,
    stats.service_names
from public."DanhGia" as dg
join order_services as os
  on os."DonHangID" = dg."DonHangID"
join service_stats as stats
  on stats."DonHangID" = dg."DonHangID"
where dg."TrangThai" = 'Hiển thị';

comment on view public.service_public_reviews is
'Public, curated service reviews: only visible review content and service names; excludes customer identifiers and order details.';

revoke all privileges on public.service_public_reviews from public;
grant select on public.service_public_reviews to anon, authenticated;
