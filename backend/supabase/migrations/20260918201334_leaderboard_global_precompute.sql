-- T2.18: global leaderboard precompute (architecture.md §4 — reads never aggregate live).
--
-- Scheduled with pg_cron inside Supabase rather than Vercel Cron: Vercel's Hobby plan rejects any schedule
-- more frequent than daily (OPS-1), and AC 4.5.2 needs data <= 15 min stale. The rebuild is one SQL function,
-- so it runs in a single transaction: a reader never sees a half-rebuilt or empty board.

-- Read path: `(season_id, scope_type, scope_id, points DESC)` per architecture.md §4.
create index if not exists leaderboard_entry_rank_idx
  on leaderboard_entry (season_id, scope_type, scope_id, points desc);

create or replace function rebuild_global_leaderboard()
returns integer
language plpgsql
as $$
declare
  v_season uuid;
  v_now timestamptz := now();
  v_count integer;
begin
  -- Two overlapping runs would interleave their delete/insert; serialize them.
  perform pg_advisory_xact_lock(hashtext('rebuild_global_leaderboard'));

  select id into v_season from season where status = 'active' limit 1;
  if v_season is null then
    return 0; -- no active season: nothing to rank, leave any existing rows untouched
  end if;

  -- Full rebuild, not an incremental upsert: a run that left `validated`/`approved`, or a user who was
  -- soft-deleted, disappears from the very next run with no separate removal step.
  delete from leaderboard_entry
   where season_id = v_season and scope_type = 'global' and scope_id = 'GLOBAL';

  -- Only points from runs whose status is `validated` or `approved` count (tech-spec.md §2.4.1: `flagged`
  -- points are held, `rejected` never count). A compensating `adjustment` row for a rejected run carries that
  -- run's id, so it is excluded together with the run's original row (net effect: nothing).
  -- `frozen_display_name` is a snapshot taken now, not a live join (database-api-spec.md §1).
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
       group by u.id, u.display_name, u.username
    ) ranked;

  get diagnostics v_count = row_count;

  -- `global` is an explicit scope row, not an absent one; `insufficient_data` is hardcoded false for global.
  insert into leaderboard_scope (season_id, scope_type, scope_id, user_count, insufficient_data, computed_at)
  values (v_season, 'global', 'GLOBAL', v_count, false, v_now)
  on conflict (season_id, scope_type, scope_id)
  do update set user_count = excluded.user_count,
                insufficient_data = false,
                computed_at = excluded.computed_at;

  return v_count;
end;
$$;

-- Internal job, never a public RPC: Supabase auto-exposes public-schema functions to anon/authenticated.
revoke all on function rebuild_global_leaderboard() from public, anon, authenticated;
grant execute on function rebuild_global_leaderboard() to service_role;

create extension if not exists pg_cron with schema pg_catalog;

do $$
begin
  perform cron.unschedule('rebuild-global-leaderboard');
exception when others then
  null; -- not scheduled yet
end;
$$;

select cron.schedule('rebuild-global-leaderboard', '*/15 * * * *', $$select public.rebuild_global_leaderboard()$$);
