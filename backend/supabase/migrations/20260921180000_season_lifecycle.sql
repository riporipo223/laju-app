-- T3.6: Season lifecycle (upcoming → active → ended).
--
-- Two hard rules, both enforced by the database rather than by convention:
--   1. At most ONE season is `active` at any time (partial unique index — holds even under concurrent writers).
--   2. The system never ends up with ZERO active seasons by itself: `POST /api/runs` cannot write a ledger row without an
--      active season (lib/point-transaction.ts throws), so a gap between seasons would turn every run submission into a 500.
--      An active season is therefore only ended together with the activation of its successor (a rollover), never alone.

alter table public.season
  add constraint season_period_check check (end_at > start_at);

create unique index season_single_active on public.season ((true)) where status = 'active';

-- Serializes every lifecycle change: the cron job and a human running the CLI at the same moment queue up rather than
-- interleave. Transaction-scoped, so it is released automatically.
create or replace function public.season_lifecycle_lock() returns void
language sql
as $$ select pg_advisory_xact_lock(hashtext('season_lifecycle')) $$;

-- Explicit, single transition. Legal moves: upcoming → active, active → ended, upcoming → ended (cancel a season that
-- never started). Activating a season while another is active ENDS the old one in the same transaction (rollover).
-- Ending the only active season on its own is refused (rule 2). Everything else raises an exception.
create or replace function public.transition_season(p_season uuid, p_to text)
returns table (season_id uuid, from_status text, to_status text, rolled_over uuid)
language plpgsql
set search_path = public
as $$
declare
  v_from text;
  v_rolled uuid;
begin
  perform public.season_lifecycle_lock();

  select s.status into v_from from public.season s where s.id = p_season for update;
  if v_from is null then
    raise exception 'season % does not exist', p_season;
  end if;
  if p_to not in ('active', 'ended') then
    raise exception 'target status must be active or ended, got %', p_to;
  end if;
  if not ((v_from = 'upcoming' and p_to in ('active', 'ended')) or (v_from = 'active' and p_to = 'ended')) then
    raise exception 'illegal season transition % → % (only upcoming → active, active → ended, upcoming → ended)', v_from, p_to;
  end if;

  if p_to = 'ended' and v_from = 'active' then
    raise exception 'refusing to end the only active season without a successor — activate the next season instead (it ends this one in the same step)';
  end if;

  if p_to = 'active' then
    update public.season set status = 'ended' where status = 'active' and id <> p_season returning id into v_rolled;
  end if;
  update public.season set status = p_to where id = p_season;

  season_id := p_season; from_status := v_from; to_status := p_to; rolled_over := v_rolled;
  return next;
end;
$$;

-- The automatic path, run by pg_cron. `p_now` is a parameter only so tests can simulate the passage of time.
--  · an active season whose end_at has passed is ended AND its successor (the earliest due `upcoming` season) activated
--    in one step; with no successor available it is left active and reported as 'overrun' (rule 2);
--  · with no active season at all (fresh install, recovery) the earliest due `upcoming` season is activated;
--  · seasons that were missed entirely are caught up one step at a time.
create or replace function public.advance_seasons(p_now timestamptz default now())
returns table (action text, season_id uuid)
language plpgsql
set search_path = public
as $$
declare
  v_active public.season;
  v_next public.season;
  v_guard integer := 0;
begin
  perform public.season_lifecycle_lock();

  loop
    v_guard := v_guard + 1;
    exit when v_guard > 12; -- a year of missed monthly seasons at most; never loop forever

    select * into v_active from public.season where status = 'active';
    select * into v_next from public.season where status = 'upcoming' and start_at <= p_now order by start_at limit 1;

    if v_active.id is null then
      exit when v_next.id is null;
      update public.season set status = 'active' where id = v_next.id;
      action := 'activated'; season_id := v_next.id; return next;
    elsif v_active.end_at <= p_now then
      if v_next.id is null then
        action := 'overrun'; season_id := v_active.id; return next;
        exit;
      end if;
      update public.season set status = 'ended' where id = v_active.id;
      action := 'ended'; season_id := v_active.id; return next;
      update public.season set status = 'active' where id = v_next.id;
      action := 'activated'; season_id := v_next.id; return next;
    else
      exit;
    end if;
  end loop;
end;
$$;

-- Internal only (same posture as rebuild_global_leaderboard / rate_limit_hit): Supabase exposes public-schema functions to
-- anon/authenticated by default, and these would let anyone move seasons.
revoke all on function public.season_lifecycle_lock() from public, anon, authenticated;
revoke all on function public.transition_season(uuid, text) from public, anon, authenticated;
revoke all on function public.advance_seasons(timestamptz) from public, anon, authenticated;
grant execute on function public.season_lifecycle_lock() to service_role;
grant execute on function public.transition_season(uuid, text) to service_role;
grant execute on function public.advance_seasons(timestamptz) to service_role;

create extension if not exists pg_cron with schema pg_catalog;

do $$
begin
  perform cron.unschedule('advance-seasons');
exception when others then
  null; -- not scheduled yet
end;
$$;

-- Hourly, at :05 — a season boundary is therefore honoured within the hour. Cheap: two indexed reads when nothing is due.
select cron.schedule('advance-seasons', '5 * * * *', $$select * from public.advance_seasons()$$);
