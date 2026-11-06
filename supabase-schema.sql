-- =====================================================================
--  保险杠生产记录 · Supabase 建表脚本
--  用法：Supabase 控制台 → 左侧 SQL Editor → New query → 全选粘贴 → Run
--  作用：建两张表 + 开权限 + 建索引。可重复执行，不会重复建。
-- =====================================================================

-- ---------- 1. 件主表：一条保险杠一行 ----------
create table if not exists public.bumpers (
  id          text primary key,                 -- 流水号 / 生产编号，就是二维码里的内容
  title       text        not null default '',  -- 备注名，如「前保险杠 1号」
  created_at  timestamptz not null default now()
);

-- ---------- 2. 记录流水表：每扫一次录一条 ----------
create table if not exists public.records (
  id          bigserial primary key,
  bumper_id   text        not null references public.bumpers(id) on delete cascade,
  ts          timestamptz not null default now(),   -- 录入时刻
  note        text        not null default '',      -- 不良现象补充说明
  author      text        not null default '',      -- 记录人
  fields      jsonb       not null default '{}'::jsonb,  -- 日期/班次/漆批次/喷涂/颜色/台车/不良
  client_uid  uuid        not null unique           -- 幂等键：断网重传不会写两条
);

-- ---------- 3. 索引：按件号查、按时间排 ----------
create index if not exists idx_records_bumper_ts on public.records (bumper_id, ts desc);
create index if not exists idx_records_ts        on public.records (ts desc);
create index if not exists idx_records_fields    on public.records using gin (fields);

-- ---------- 4. 开权限（这是前端用 anon key 直连的关键） ----------
alter table public.bumpers enable row level security;
alter table public.records enable row level security;

-- 内网小工具：允许匿名读写。若将来要区分「谁能改」，把这两组 drop 掉后
-- 再加 auth.uid() 相关策略即可，现在先保证能用。
drop policy if exists bumpers_anon_read   on public.bumpers;
drop policy if exists bumpers_anon_write  on public.bumpers;
drop policy if exists records_anon_read   on public.records;
drop policy if exists records_anon_write  on public.records;

create policy bumpers_anon_read  on public.bumpers for select using (true);
create policy bumpers_anon_write on public.bumpers for all    using (true) with check (true);
create policy records_anon_read  on public.records for select using (true);
create policy records_anon_write on public.records for all    using (true) with check (true);

-- ---------- 5. 自检：跑完这两句应该各返回一行 ----------
-- select count(*) as bumpers_rows from public.bumpers;
-- select count(*) as records_rows  from public.records;
