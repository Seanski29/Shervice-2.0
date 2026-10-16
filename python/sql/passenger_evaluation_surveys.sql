-- Anonymous passenger evaluation surveys.
-- Run this migration in Supabase SQL Editor before enabling the staff survey page.

begin;

alter table public.evaluation
  add column if not exists source text not null default 'staff',
  add column if not exists survey_id uuid;

alter table public.evaluation
  drop constraint if exists evaluation_source_check;

alter table public.evaluation
  add constraint evaluation_source_check
  check (source in ('staff', 'passenger'));

create table if not exists public.passenger_evaluation_survey (
  survey_id uuid primary key default gen_random_uuid(),
  token_hash text not null unique,
  created_by uuid null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  is_active boolean not null default true
);

create index if not exists idx_evaluation_driver_source
  on public.evaluation (driver_id, source, submit_date desc);

create index if not exists idx_evaluation_survey_id
  on public.evaluation (survey_id);

create index if not exists idx_passenger_survey_active_expiry
  on public.passenger_evaluation_survey (is_active, expires_at desc);

alter table public.evaluation
  drop constraint if exists evaluation_survey_fk;

alter table public.evaluation
  add constraint evaluation_survey_fk
  foreign key (survey_id)
  references public.passenger_evaluation_survey (survey_id)
  on delete set null;

commit;
