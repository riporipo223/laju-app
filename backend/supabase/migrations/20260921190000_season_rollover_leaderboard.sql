-- T3.7: rank reset on season transition.
--
-- Most of the mechanic already holds by construction, and T3.7 proves it rather than rebuilding it: the leaderboard is computed
-- per `season_id` from that season's own ledger rows (a user with no points in the new season simply has no row — no carried-over
-- lifetime points), `user.total_points`/`current_level` are SUM(ledger) over ALL seasons (never season-scoped, so a transition
-- cannot touch them), and a flagged run that resolves after its season ended writes its compensating row into the ORIGINAL season.
--
-- Two gaps closed here, both about WHEN the leaderboard is computed relative to a transition:
--   1. The season being ended used to keep whatever the 15-minute job had last written — up to 15 minutes of points missing from
--      its FINAL standings. It is now rebuilt one last time, while still active, immediately before it is ended.
--   2. The new season used to have no leaderboard rows and no `leaderboard_scope` row until the next 15-minute run, so
--      `computed_at` was null and the board looked unbuilt. It is now built (empty, or with whatever already exists) the moment it
--      is activated.
-- Redefines the two functions from T3.6 (create or replace); everything else about them is unchanged.

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
    -- Final standings of the season about to end (rebuild works on whichever season is active right now).
    perform public.rebuild_global_leaderboard();
    update public.season set status = 'ended' where status = 'active' and id <> p_season returning id into v_rolled;
  end if;
  update public.season set status = p_to where id = p_season;
  if p_to = 'active' then
    perform public.rebuild_global_leaderboard(); -- the new season's board exists from the first second
  end if;

  season_id := p_season; from_status := v_from; to_status := p_to; rolled_over := v_rolled;
  return next;
end;
$$;

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
    exit when v_guard > 12;

    select * into v_active from public.season where status = 'active';
    select * into v_next from public.season where status = 'upcoming' and start_at <= p_now order by start_at limit 1;

    if v_active.id is null then
      exit when v_next.id is null;
      update public.season set status = 'active' where id = v_next.id;
      perform public.rebuild_global_leaderboard();
      action := 'activated'; season_id := v_next.id; return next;
    elsif v_active.end_at <= p_now then
      if v_next.id is null then
        action := 'overrun'; season_id := v_active.id; return next;
        exit;
      end if;
      perform public.rebuild_global_leaderboard(); -- final standings of the season being ended
      update public.season set status = 'ended' where id = v_active.id;
      action := 'ended'; season_id := v_active.id; return next;
      update public.season set status = 'active' where id = v_next.id;
      perform public.rebuild_global_leaderboard(); -- fresh board for the new season
      action := 'activated'; season_id := v_next.id; return next;
    else
      exit;
    end if;
  end loop;
end;
$$;

revoke all on function public.transition_season(uuid, text) from public, anon, authenticated;
revoke all on function public.advance_seasons(timestamptz) from public, anon, authenticated;
grant execute on function public.transition_season(uuid, text) to service_role;
grant execute on function public.advance_seasons(timestamptz) to service_role;
