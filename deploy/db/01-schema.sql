-- =====================================================================
--  保险杠生产记录 · 建表脚本（自建 Postgres 版）
--  由原 supabase-schema.sql 移植：表结构、索引、RLS 策略完全一致，
--  只把「Supabase 控制台」换成 docker 初始化时自动执行。
--  可重复执行。
-- =====================================================================

-- ---------- 1. 件主表：一条保险杠一行 ----------
create table if not exists public.bumpers (
  id          text primary key,                 -- 流水号 / 生产编号，就是二维码里的内容
  title       text        not null default '',  -- 备注名
  created_at  timestamptz not null default now()
);

-- ---------- 2. 记录流水表：每扫一次录一条 ----------
create table if not exists public.records (
  id          bigserial primary key,
  bumper_id   text        not null references public.bumpers(id) on delete cascade,
  ts          timestamptz not null default now(),
  note        text        not null default '',
  author      text        not null default '',
  fields      jsonb       not null default '{}'::jsonb,
  client_uid  uuid        not null unique          -- 幂等键：断网重传不会写两条
);

-- ---------- 3. 索引 ----------
create index if not exists idx_records_bumper_ts on public.records (bumper_id, ts desc);
create index if not exists idx_records_ts        on public.records (ts desc);
create index if not exists idx_records_fields    on public.records using gin (fields);

-- ---------- 4. 行级安全：与线上保持一致（匿名可读写） ----------
alter table public.bumpers enable row level security;
alter table public.records enable row level security;

drop policy if exists bumpers_anon_read   on public.bumpers;
drop policy if exists bumpers_anon_write  on public.bumpers;
drop policy if exists records_anon_read   on public.records;
drop policy if exists records_anon_write  on public.records;

create policy bumpers_anon_read  on public.bumpers for select using (true);
create policy bumpers_anon_write on public.bumpers for all    using (true) with check (true);
create policy records_anon_read  on public.records for select using (true);
create policy records_anon_write on public.records for all    using (true) with check (true);
