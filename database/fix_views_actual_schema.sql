-- ============================================================
-- FIX SCRIPT: Cập nhật Views theo cấu trúc DB thực tế
-- Chạy toàn bộ script này trong Supabase SQL Editor
-- 
-- Cấu trúc DB thực tế:
--   inventory   : tag_id, bin, stock_up_date, id
--   master_data : tag_id(=batch), lp_no(=stock_code), qty, wh_location(=warehouse), create_date
-- ============================================================

-- ============================================================
-- BƯỚC 1: XÓA VIEWS CŨ (nếu có) để tạo lại đúng
-- ============================================================
drop view if exists vw_summary_analysis;
drop view if exists vw_kho_thanh_pham;

-- ============================================================
-- BƯỚC 2: TẠO LẠI vw_kho_thanh_pham
-- Mapping đúng với cột thực tế:
--   master_data.tag_id     = BATCH (dùng để join với inventory.tag_id)
--   master_data.lp_no      = Stock Code
--   master_data.wh_location = Warehouse
--   inventory.stock_up_date = stock_in_date
-- ============================================================
create or replace view vw_kho_thanh_pham as
select
  -- LP.No / Stock Code
  coalesce(m.lp_no, 'No data')                              as lp_no,
  
  -- Feature: trích ký tự 2-5 từ lp_no (công thức MID Excel: =MID(text,2,4))
  case
    when m.lp_no is not null and length(trim(m.lp_no)) >= 5
      then substring(trim(m.lp_no) from 2 for 4)
    else 'No data'
  end                                                        as feature,
  
  -- Actual Qty từ master_data
  coalesce(m.qty, 0)                                        as qty,
  
  -- Warehouse (cột thực là wh_location)
  coalesce(m.wh_location, 'No data')                       as warehouse,
  
  -- CreateDate từ master_data
  coalesce(m.create_date, 'No data')                       as create_date,
  
  -- Stock In Date (cột thực là stock_up_date trong inventory)
  i.stock_up_date                                           as stock_in_date,
  
  -- Tag ID từ inventory
  i.tag_id                                                  as tag_id,
  
  -- Bin từ inventory
  i.bin                                                     as bin,
  
  -- ID ảo tuyệt đối để xuất kho chính xác
  i.id                                                      as inventory_id

from inventory i
left join master_data m
  on trim(lower(i.tag_id)) = trim(lower(m.tag_id));

-- ============================================================
-- BƯỚC 3: TẠO LẠI vw_summary_analysis
-- Dùng vw_kho_thanh_pham đã được fix ở trên
-- iScala: chỉ tính dòng warehouse IN ('60', '01')
-- Diff %: diff / iscala * 100, tránh chia cho 0
-- ============================================================
create or replace view vw_summary_analysis as
with actual_by_feature as (
  select
    feature,
    sum(qty)::numeric as actual
  from vw_kho_thanh_pham
  where feature is not null
    and feature <> 'No data'
  group by feature
),
iscala_by_feature as (
  select
    -- Tách feature từ lp_no theo công thức MID(text,2,4)
    substring(trim(lp_no) from 2 for 4)  as feature,
    sum(qty)::numeric                     as iscala
  from master_data
  where wh_location in ('60', '01')
    and lp_no is not null
    and length(trim(lp_no)) >= 5
  group by substring(trim(lp_no) from 2 for 4)
)
select
  a.feature,
  coalesce(a.actual, 0)                                          as actual,
  coalesce(i.iscala, 0)                                          as iscala,
  coalesce(a.actual, 0) - coalesce(i.iscala, 0)                 as diff,
  case
    when coalesce(i.iscala, 0) = 0 then 0::numeric
    else round(
      ((coalesce(a.actual, 0) - coalesce(i.iscala, 0)) / i.iscala) * 100,
      2
    )
  end                                                            as diff_percent
from actual_by_feature a
left join iscala_by_feature i
  on a.feature = i.feature
order by a.feature;

-- ============================================================
-- BƯỚC 4: RPC REPLACE_MASTER_DATA
-- Cập nhật theo tên cột thực tế (lp_no, wh_location, tag_id)
-- ============================================================
create or replace function replace_master_data(payload jsonb)
returns void
language plpgsql
security definer
as $$
begin
  -- Xóa dữ liệu cũ an toàn
  delete from master_data;

  -- Chèn dữ liệu mới từ payload
  -- Hỗ trợ cả 2 tên cột cũ/mới để tương thích CSV
  insert into master_data (tag_id, lp_no, qty, wh_location, create_date)
  select
    -- batch / tag_id / BATCH
    coalesce(
      nullif(trim(item->>'batch'), ''),
      nullif(trim(item->>'tag_id'), ''),
      nullif(trim(item->>'BATCH'), '')
    ),
    -- stock_code / lp_no / LP.No
    coalesce(
      nullif(trim(item->>'stock_code'), ''),
      nullif(trim(item->>'lp_no'), ''),
      nullif(trim(item->>'LP.No'), '')
    ),
    -- qty
    nullif(trim(item->>'qty'), '')::numeric,
    -- warehouse / wh_location
    coalesce(
      nullif(trim(item->>'warehouse'), ''),
      nullif(trim(item->>'wh_location'), '')
    ),
    -- create_date / createdate / CREATEDATE
    coalesce(
      nullif(trim(item->>'create_date'), ''),
      nullif(trim(item->>'createdate'), ''),
      nullif(trim(item->>'CREATEDATE'), '')
    )
  from jsonb_array_elements(payload) as item;
end;
$$;

-- ============================================================
-- BƯỚC 5: BẬT RLS VÀ TẠO POLICIES (bỏ qua nếu đã có)
-- ============================================================

-- Bật RLS
alter table inventory      enable row level security;
alter table master_data    enable row level security;
alter table hang_phu_kien  enable row level security;

-- Xóa policies cũ trước (tránh lỗi trùng tên)
drop policy if exists "allow_anon_select_inventory"        on inventory;
drop policy if exists "allow_anon_insert_inventory"        on inventory;
drop policy if exists "allow_anon_update_inventory"        on inventory;
drop policy if exists "allow_anon_delete_inventory"        on inventory;
drop policy if exists "allow_anon_select_master_data"      on master_data;
drop policy if exists "allow_anon_insert_master_data"      on master_data;
drop policy if exists "allow_anon_update_master_data"      on master_data;
drop policy if exists "allow_anon_delete_master_data"      on master_data;
drop policy if exists "allow_anon_select_hang_phu_kien"    on hang_phu_kien;
drop policy if exists "allow_anon_insert_hang_phu_kien"    on hang_phu_kien;
drop policy if exists "allow_anon_update_hang_phu_kien"    on hang_phu_kien;
drop policy if exists "allow_anon_delete_hang_phu_kien"    on hang_phu_kien;

-- Tạo lại Policies cho role anon (public, không cần login)
-- inventory
create policy "allow_anon_select_inventory"     on inventory for select     to anon using (true);
create policy "allow_anon_insert_inventory"     on inventory for insert     to anon with check (true);
create policy "allow_anon_update_inventory"     on inventory for update     to anon using (true) with check (true);
create policy "allow_anon_delete_inventory"     on inventory for delete     to anon using (true);

-- master_data
create policy "allow_anon_select_master_data"   on master_data for select   to anon using (true);
create policy "allow_anon_insert_master_data"   on master_data for insert   to anon with check (true);
create policy "allow_anon_update_master_data"   on master_data for update   to anon using (true) with check (true);
create policy "allow_anon_delete_master_data"   on master_data for delete   to anon using (true);

-- hang_phu_kien
create policy "allow_anon_select_hang_phu_kien" on hang_phu_kien for select to anon using (true);
create policy "allow_anon_insert_hang_phu_kien" on hang_phu_kien for insert to anon with check (true);
create policy "allow_anon_update_hang_phu_kien" on hang_phu_kien for update to anon using (true) with check (true);
create policy "allow_anon_delete_hang_phu_kien" on hang_phu_kien for delete to anon using (true);

-- ============================================================
-- BƯỚC 6: Kiểm tra kết quả
-- ============================================================

-- Xem thử 5 dòng view tồn kho
-- select * from vw_kho_thanh_pham limit 5;

-- Xem thử summary
-- select * from vw_summary_analysis limit 10;
