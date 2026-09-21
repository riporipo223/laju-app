-- T2.20a (SEC-9): API rate limiting, kept inside Postgres — no new vendor, and unlike in-memory limiting it
-- survives serverless cold starts and is shared by every instance.
--
-- Fixed-window counter: one row per (key, window). The caller puts the window length INTO the key
-- ("user:<id>:60") because a minute bucket and an hour bucket share a window_start at every hour boundary and
-- would otherwise merge into one row.

create table public.rate_limit_bucket (
  key          text        not null,
  window_start timestamptz not null,
  count        integer     not null default 0,
  primary key (key, window_start)
);

-- Same posture as every table since 20260919150457: RLS on, no policies, no grants to the public roles. Only the
-- backend (service_role) touches this.
alter table public.rate_limit_bucket enable row level security;
revoke all on public.rate_limit_bucket from anon, authenticated;

-- Atomic: the upsert takes the row lock, so N concurrent callers are serialized on the counter and exactly
-- `p_limit` of them see count <= p_limit. A read-then-write limiter (the naive version) lets a concurrent burst
-- straight through.
create or replace function public.rate_limit_hit(p_key text, p_limit integer, p_window_seconds integer)
returns table (allowed boolean, retry_after_seconds integer)
language plpgsql
set search_path = public
as $$
declare
  v_start timestamptz := to_timestamp(floor(extract(epoch from now()) / p_window_seconds) * p_window_seconds);
  v_count integer;
begin
  insert into public.rate_limit_bucket as b (key, window_start, count)
  values (p_key, v_start, 1)
  on conflict (key, window_start) do update set count = b.count + 1
  returning b.count into v_count;

  allowed := v_count <= p_limit;
  retry_after_seconds := greatest(
    1,
    ceil(extract(epoch from (v_start + make_interval(secs => p_window_seconds) - now())))::integer
  );
  return next;
end;
$$;

-- Internal: Supabase auto-exposes public-schema functions to anon/authenticated over PostgREST, and this one
-- would let anyone burn another caller's budget.
revoke all on function public.rate_limit_hit(text, integer, integer) from public, anon, authenticated;
grant execute on function public.rate_limit_hit(text, integer, integer) to service_role;

-- Longest window in use is one hour; keep two so a bucket is never deleted while it can still be counted.
create extension if not exists pg_cron with schema pg_catalog;

do $$
begin
  perform cron.unschedule('cleanup-rate-limit-buckets');
exception when others then
  null; -- not scheduled yet
end;
$$;

select cron.schedule(
  'cleanup-rate-limit-buckets',
  '*/15 * * * *',
  $$delete from public.rate_limit_bucket where window_start < now() - interval '2 hours'$$
);
