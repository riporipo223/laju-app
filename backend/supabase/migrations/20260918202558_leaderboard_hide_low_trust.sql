-- T2.19: hide low-trust users from the public leaderboard.
--
-- Done in the precompute (not at read time) so `rank`, `me.rank` and `leaderboard_scope.user_count` all agree:
-- filtering rows out of an already-ranked board at read time would leave gaps (1, 2, 4, ...) and make a
-- caller's own `me.rank` disagree with the list they are looking at.
--
-- Cutoff 0.5 is a product decision (user-approved 2026-09-19): roughly 5 net HIGH-confidence flags in the
-- 30-day trust window (tech-spec.md §2.4 — floor 0.3, -0.10 per HIGH flag, -0.05 per LOW flag). It lives in
-- exactly one place, `v_min_trust` below. A user's trust changes between runs, so a hide/unhide takes effect
-- on the next 15-minute rebuild.

create or replace function rebuild_global_leaderboard()
returns integer
language plpgsql
as $$
declare
  v_min_trust constant double precision := 0.5;
  v_season uuid;
  v_now timestamptz := now();
  v_count integer;
begin
  perform pg_advisory_xact_lock(hashtext('rebuild_global_leaderboard'));

  select id into v_season from season where status = 'active' limit 1;
  if v_season is null then
    return 0;
  end if;

  delete from leaderboard_entry
   where season_id = v_season and scope_type = 'global' and scope_id = 'GLOBAL';

  insert into leaderboard_entry
    (season_id, scope_type, scope_id, user_id, frozen_display_name, points, rank, computed_at)
  select v_season, 'global', 'GLOBAL', ranked.user_id, ranked.name, ranked.points,
         rank() over (order by ranked.points desc)::integer, v_now
    from (
      select u.id as user_id,
             coalesce(u.display_name, u.username) as name,
             sum(pt.amount)::integer as points
        from point_transaction pt
        join run r on r.id = pt.run_id
        join "user" u on u.id = pt.user_id
       where pt.season_id = v_season
         and r.status in ('validated', 'approved')
         and u.deleted_at is null
         and u.trust_score >= v_min_trust
       group by u.id, u.display_name, u.username
    ) ranked;

  get diagnostics v_count = row_count;

  insert into leaderboard_scope (season_id, scope_type, scope_id, user_count, insufficient_data, computed_at)
  values (v_season, 'global', 'GLOBAL', v_count, false, v_now)
  on conflict (season_id, scope_type, scope_id)
  do update set user_count = excluded.user_count,
                insufficient_data = false,
                computed_at = excluded.computed_at;

  return v_count;
end;
$$;
