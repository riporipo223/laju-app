/**
 * T3.6's admin-triggered path: inspect and drive the season lifecycle by hand. The automatic path is the hourly pg_cron
 * job `advance-seasons`; this reuses the SAME database functions, so a human and the job can never disagree about the rules
 * (at most one active season; an active season is only ended together with its successor's activation).
 *
 * Usage (from backend/):
 *   npx tsx --env-file=.env.local scripts/season.ts list
 *   npx tsx --env-file=.env.local scripts/season.ts create "Season 2 — 2026" 2026-12-01T00:00:00Z 2027-02-28T23:59:59Z
 *   npx tsx --env-file=.env.local scripts/season.ts activate <season_id>   # rolls the current active season over
 *   npx tsx --env-file=.env.local scripts/season.ts cancel <season_id>     # upcoming → ended, never started
 *   npx tsx --env-file=.env.local scripts/season.ts advance                # what the hourly job does, right now
 */
import { supabaseAdmin } from "../lib/supabase";

const [command, ...args] = process.argv.slice(2);

async function main() {
  switch (command) {
    case "list": {
      const { data, error } = await supabaseAdmin.from("season").select("id, name, status, start_at, end_at").order("start_at");
      if (error) throw new Error(error.message);
      console.table(data);
      return;
    }
    case "create": {
      const [name, startAt, endAt] = args;
      if (!name || !startAt || !endAt || Number.isNaN(Date.parse(startAt)) || Number.isNaN(Date.parse(endAt))) {
        throw new Error('usage: create "<name>" <start ISO 8601> <end ISO 8601>');
      }
      const { data, error } = await supabaseAdmin
        .from("season")
        .insert({ name, start_at: startAt, end_at: endAt, status: "upcoming" })
        .select("id, name, status, start_at, end_at")
        .single();
      if (error) throw new Error(error.message);
      console.log("created (upcoming — it starts by itself when its start_at passes):", data);
      return;
    }
    case "activate":
    case "cancel": {
      const [id] = args;
      if (!id) throw new Error(`usage: ${command} <season_id>`);
      const { data, error } = await supabaseAdmin.rpc("transition_season", {
        p_season: id,
        p_to: command === "activate" ? "active" : "ended",
      });
      if (error) throw new Error(error.message);
      console.log(data);
      return;
    }
    case "advance": {
      const { data, error } = await supabaseAdmin.rpc("advance_seasons");
      if (error) throw new Error(error.message);
      console.log(data.length ? data : "nothing due");
      return;
    }
    default:
      throw new Error("usage: season.ts list | create | activate | cancel | advance (see the header comment)");
  }
}

main().catch((failure) => {
  console.error(failure instanceof Error ? failure.message : failure);
  process.exit(1);
});
