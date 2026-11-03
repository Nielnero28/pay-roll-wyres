-- Wyres Payroll Desk: Supabase schema with role-based access (Admin / Secretary)
-- Run once in Supabase: SQL Editor > New query > paste > Run.

create table public.profiles (
  id uuid primary key references auth.users on delete cascade,
  role text not null check (role in ('admin','secretary')),
  full_name text
);

create or replace function public.my_role() returns text
language sql stable security definer set search_path = public as
$$ select role from public.profiles where id = auth.uid() $$;
revoke all on function public.my_role() from public, anon;
grant execute on function public.my_role() to authenticated;

create table public.settings (
  id int primary key default 1 check (id = 1),
  company text not null default 'Wyres Hair Products',
  cur text not null default '₱',
  ot numeric not null default 1.25,
  lm numeric not null default 1,
  tax numeric not null default 10,
  con numeric not null default 4.5,
  hpd numeric not null default 8
);
insert into public.settings default values;

create table public.employees (
  id bigint generated always as identity primary key,
  name text not null,
  pos text,
  rate numeric not null default 0 check (rate >= 0),
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.periods (
  id bigint generated always as identity primary key,
  label text not null,
  start_date date,
  end_date date,
  status text not null default 'draft' check (status in ('draft','submitted','approved')),
  created_at timestamptz not null default now()
);

create table public.lines (
  period_id bigint not null references public.periods on delete cascade,
  emp_id bigint not null references public.employees on delete restrict,
  days numeric not null default 0,
  ot numeric not null default 0,
  late numeric not null default 0,
  al numeric not null default 0,
  od numeric not null default 0,
  rate numeric not null default 0,
  primary key (period_id, emp_id),
  check (days >= 0 and ot >= 0 and late >= 0 and al >= 0 and od >= 0)
);

create table public.audit_log (
  id bigint generated always as identity primary key,
  at timestamptz not null default now(),
  user_id uuid default auth.uid(),
  role text default public.my_role(),
  action text not null
);

-- Server-side rules the browser cannot bypass
create or replace function public.guard_employee() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is not null and public.my_role() is distinct from 'admin' then
    if tg_op = 'INSERT' then new.rate := 0; new.active := true;
    else new.rate := old.rate; new.active := old.active; end if;
  end if;
  return new;
end $$;
create trigger employees_guard before insert or update on public.employees
for each row execute function public.guard_employee();

create or replace function public.guard_period() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is not null and public.my_role() is distinct from 'admin' then
    if tg_op = 'INSERT' then new.status := 'draft';
    elsif old.status <> 'draft' or new.status not in ('draft','submitted') then
      raise exception 'Only the Admin can change this payroll period';
    end if;
  end if;
  if tg_op = 'UPDATE' and new.status = 'approved' and old.status <> 'approved' then
    update public.lines l set rate = e.rate
    from public.employees e where l.period_id = new.id and e.id = l.emp_id;
  end if;
  return new;
end $$;
create trigger periods_guard before insert or update on public.periods
for each row execute function public.guard_period();

create or replace function public.guard_line() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.rate := (select rate from public.employees where id = new.emp_id);
  return new;
end $$;
create trigger lines_guard before insert or update on public.lines
for each row execute function public.guard_line();

-- Row-level security
alter table public.profiles  enable row level security;
alter table public.settings  enable row level security;
alter table public.employees enable row level security;
alter table public.periods   enable row level security;
alter table public.lines     enable row level security;
alter table public.audit_log enable row level security;

create policy profiles_own on public.profiles for select to authenticated using (id = auth.uid());

create policy settings_read  on public.settings for select to authenticated using (public.my_role() is not null);
create policy settings_admin on public.settings for update to authenticated
  using (public.my_role() = 'admin') with check (public.my_role() = 'admin');

create policy emp_read  on public.employees for select to authenticated using (public.my_role() is not null);
create policy emp_add   on public.employees for insert to authenticated with check (public.my_role() is not null);
create policy emp_edit  on public.employees for update to authenticated
  using (public.my_role() is not null) with check (public.my_role() is not null);

create policy per_read  on public.periods for select to authenticated using (public.my_role() is not null);
create policy per_add   on public.periods for insert to authenticated with check (public.my_role() is not null);
create policy per_edit  on public.periods for update to authenticated
  using (public.my_role() is not null) with check (public.my_role() is not null);

create policy line_read on public.lines for select to authenticated using (public.my_role() is not null);
create policy line_add  on public.lines for insert to authenticated
  with check (public.my_role() is not null and exists (select 1 from public.periods p where p.id = period_id and p.status = 'draft'));
create policy line_edit on public.lines for update to authenticated
  using (public.my_role() is not null and exists (select 1 from public.periods p where p.id = period_id and p.status = 'draft'))
  with check (exists (select 1 from public.periods p where p.id = period_id and p.status = 'draft'));
create policy line_del  on public.lines for delete to authenticated
  using (public.my_role() is not null and exists (select 1 from public.periods p where p.id = period_id and p.status = 'draft'));

create policy log_add  on public.audit_log for insert to authenticated
  with check (user_id = auth.uid() and public.my_role() is not null);
create policy log_read on public.audit_log for select to authenticated using (public.my_role() = 'admin');

-- Privileges: nothing for anonymous visitors
revoke all on all tables in schema public from anon;
grant select on public.profiles, public.settings to authenticated;
grant update on public.settings to authenticated;
grant select, insert, update on public.employees, public.periods to authenticated;
grant select, insert, update, delete on public.lines to authenticated;
grant select, insert on public.audit_log to authenticated;
grant usage on all sequences in schema public to authenticated;

-- AFTER creating the two users in Authentication > Users, assign their roles
-- (replace the emails, then run these two lines):
-- insert into public.profiles (id, role, full_name) select id, 'admin', 'Admin' from auth.users where email = 'ADMIN_EMAIL_HERE';
-- insert into public.profiles (id, role, full_name) select id, 'secretary', 'Secretary' from auth.users where email = 'SECRETARY_EMAIL_HERE';
