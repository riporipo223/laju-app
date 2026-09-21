-- T3.8: keep each season's final result forever, with the league it ended in.
--
-- `leaderboard_entry` already keeps an ended season's rows (rebuilds only touch the ACTIVE season), so the final rank was never
-- lost. What was missing: (1) the final LEAGUE — deriving it later from points would silently change every past season
-- whenever the bands are recalibrated (tech-spec.md §2.5 says to), and (2) a retrieval path. `season_result` is written ONCE, in
-- the same transaction that ends the season (right after its final rebuild), and never updated — `on conflict do nothing`.
--
-- The bands now live in `league_band` so the freeze can run inside the database, where seasons end (pg_cron). backend/lib/
-- season-league.ts LEAGUE_BANDS is the code copy used for live `me.league`; a test asserts the two are identical.
-- Changing a band = change BOTH (the parity test fails otherwise); past seasons keep the league they finished with.

create table public.league_band (
  league     text primary key check (league in ('bronze', 'silver', 'gold', 'platinum')),
  min_points integer not null unique check (min_points >= 0)
);
insert into public.league_band (league, min_points)
values ('bronze', 0), ('silver', 80), ('gold', 250), ('platinum', 600);

create table public.season_result (
  season_id    uuid        not null references public.season (id),
  user_id      uuid        not null references public."user" (id),
  final_rank   integer     not null,
  final_points integer     not null,
  league       text        not null references public.league_band (league),
  participants integer     not null,
  frozen_at    timestamptz not null default now(),
  primary key (season_id, user_id)
);
create index season_result_user_idx on public.season_result (user_id);

-- Same posture as every table since 20260919150457: RLS on, no policies, no grants to the public roles.
alter table public.league_band enable row level security;
alter table public.season_result enable row level security;
revoke all on public.league_band from anon, authenticated;
revoke all on public.season_result from anon, authenticated;

create or replace function public.freeze_season_results(p_season uuid)
returns integer
language plpgsql
set search_path = public
as $$
declare
  v_count integer;
begin
  insert into season_result (season_id, user_id, final_rank, final_points, league, participants)
  select e.season_id, e.user_id, e.rank, e.points,
         (select b.league from league_band b where b.min_points <= e.points order by b.min_points desc limit 1),
         count(*) over ()::integer
    from leaderboard_entry e
   where e.season_id = p_season and e.scope_type = 'global' and e.scope_id = 'GLOBAL'
  on conflict (season_id, user_id) do nothing;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke all on function public.freeze_season_results(uuid) from public, anon, authenticated;
grant execute on function public.freeze_season_results(uuid) to service_role;

-- transition_season / advance_seasons: unchanged from T3.7 except each calls freeze_season_results for the season it ends,
-- immediately after that season's final rebuild and before it is marked ended.
create or replace function public.transition_season(p_season uuid, p_to text)
returns table (season_id uuid, from_status text, to_status text, rolled_over uuid)
language plpgsql
set search_path = public
as $$
declare
  v_from text;
  v_rolled uuid;
  v_ending uuid;
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
    select s.id into v_ending from public.season s where s.status = 'active' and s.id <> p_season;
    if v_ending is not null then
      perform public.freeze_season_results(v_ending);
    end if;
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
      perform public.freeze_season_results(v_active.id);
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
