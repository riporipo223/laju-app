-- T3.7a: one user's points in one season — the SAME quantity `rebuild_global_leaderboard()` stores as
-- `leaderboard_entry.points` (ledger rows of runs that are validated/approved; a compensating row carries its run's id, so a
-- rejected run nets to nothing and a flagged run counts nothing until resolved). Deliberately NOT filtered by trust_score:
-- that filter only hides a user from the PUBLIC board, while a user's own league is their own number. Deleted users are not
-- filtered either — the route only asks for the signed-in, non-deleted caller.
create or replace function public.season_points(p_user uuid, p_season uuid)
returns integer
language sql
stable
set search_path = public
as $$
  select coalesce(sum(pt.amount), 0)::integer
    from point_transaction pt
    join run r on r.id = pt.run_id
   where pt.user_id = p_user
     and pt.season_id = p_season
     and r.status in ('validated', 'approved');
$$;

revoke all on function public.season_points(uuid, uuid) from public, anon, authenticated;
grant execute on function public.season_points(uuid, uuid) to service_role;
