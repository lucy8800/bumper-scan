-- 角色与授权：PostgREST 用 authenticator 登录，再 SET ROLE anon 对外提供匿名读写。
-- :'pw' 由 99-roles.sh 通过 psql -v 传入，避免密码写进文件。
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticator') then
    create role authenticator login noinherit;
  end if;
end
$$;

alter role authenticator with login noinherit password :'pw';
grant anon to authenticator;

grant usage on schema public to anon;
grant select, insert, update, delete on all tables in schema public to anon;
grant usage, select on all sequences in schema public to anon;

alter default privileges in schema public
  grant select, insert, update, delete on tables to anon;
alter default privileges in schema public
  grant usage, select on sequences to anon;
