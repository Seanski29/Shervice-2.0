-- Run once in the shared Supabase database.
create table if not exists public.payroll_settings (
    setting_key text primary key default 'default',
    regular_pay numeric(12, 2) not null default 600,
    half_day_deduction numeric(12, 2) not null default 300,
    absent_deduction numeric(12, 2) not null default 600,
    overtime_pay numeric(12, 2) not null default 100,
    updated_at timestamptz not null default timezone('utc', now()),
    constraint payroll_settings_non_negative check (
        regular_pay >= 0
        and half_day_deduction >= 0
        and absent_deduction >= 0
        and overtime_pay >= 0
    )
);

insert into public.payroll_settings (setting_key)
values ('default')
on conflict (setting_key) do nothing;

alter table public.payroll_settings enable row level security;

-- The Flask service uses the configured Supabase service role for this table.
-- Do not expose this table directly to anonymous clients.
