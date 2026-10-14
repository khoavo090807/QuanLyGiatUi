drop view if exists public.service_public_reviews;

create or replace function private.get_service_public_reviews(
  p_service_id integer,
  p_filter text default 'all',
  p_offset integer default 0,
  p_limit integer default 10
)
returns table (
  review_id integer,
  service_id integer,
  service_name text,
  rating integer,
  comment text,
  shop_response text,
  reviewed_at timestamp without time zone,
  service_count integer,
  service_names text[]
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if coalesce(current_setting('request.jwt.claim.role', true), '') not in ('anon', 'authenticated') then
    return;
  end if;

  if p_filter not in ('all', 'single', 'mixed') then
    return;
  end if;

  return query
  with order_services as (
    select distinct ct."DonHangID", dv."DichVuID", dv."TenDichVu"
    from public."ChiTietDonHang" as ct
    join public."DichVu" as dv on dv."DichVuID" = ct."DichVuID"
  ),
  service_stats as (
    select os."DonHangID",
      count(*)::integer as service_count,
      array_agg(os."TenDichVu"::text order by os."TenDichVu") as service_names
    from order_services as os
    group by os."DonHangID"
  )
  select dg."DanhGiaID",
    os."DichVuID",
    os."TenDichVu"::text,
    dg."SoSao",
    dg."BinhLuan"::text,
    dg.shop_response,
    dg."NgayDanhGia",
    stats.service_count,
    stats.service_names
  from public."DanhGia" as dg
  join order_services as os on os."DonHangID" = dg."DonHangID"
  join service_stats as stats on stats."DonHangID" = dg."DonHangID"
  where dg."TrangThai" = 'Hiển thị'
    and os."DichVuID" = p_service_id
    and (p_filter = 'all'
      or (p_filter = 'single' and stats.service_count = 1)
      or (p_filter = 'mixed' and stats.service_count > 1))
  order by dg."NgayDanhGia" desc, dg."DanhGiaID" desc
  offset greatest(coalesce(p_offset, 0), 0)
  limit least(greatest(coalesce(p_limit, 10), 1), 1000);
end;
$$;

revoke all on function private.get_service_public_reviews(integer, text, integer, integer) from public, anon, authenticated, service_role;
grant usage on schema private to anon, authenticated;
grant execute on function private.get_service_public_reviews(integer, text, integer, integer) to anon, authenticated;

create or replace function public.get_service_public_reviews(
  p_service_id integer,
  p_filter text default 'all',
  p_offset integer default 0,
  p_limit integer default 10
)
returns table (
  review_id integer,
  service_id integer,
  service_name text,
  rating integer,
  comment text,
  shop_response text,
  reviewed_at timestamp without time zone,
  service_count integer,
  service_names text[]
)
language sql
stable
security invoker
set search_path = ''
as $$
  select *
  from private.get_service_public_reviews(p_service_id, p_filter, p_offset, p_limit);
$$;

revoke all on function public.get_service_public_reviews(integer, text, integer, integer) from public;
grant execute on function public.get_service_public_reviews(integer, text, integer, integer) to anon, authenticated;

notify pgrst, 'reload schema';
