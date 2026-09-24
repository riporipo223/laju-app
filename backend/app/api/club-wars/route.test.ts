import { beforeEach, describe, expect, it, vi } from "vitest";

// Route-level tests. The Supabase repository and auth are mocked; the Premium check is NOT —
// these tests run the real always-deny stub, proving the production wiring refuses every challenge.
const requireUserMock = vi.fn();
const repo = {
  getMembership: vi.fn(),
  existingClubIds: vi.fn(),
  createWar: vi.fn(),
  getWar: vi.fn(),
  setInviteStatus: vi.fn(),
  dissolveWar: vi.fn(),
  activateWar: vi.fn(),
  listMembers: vi.fn(),
  insertParticipants: vi.fn(),
  listExpiredPendingWarIds: vi.fn(),
  listActiveWarsStartedBefore: vi.fn(),
  listParticipants: vi.fn(),
  listRuns: vi.fn(),
  recordResult: vi.fn(),
  listWarsForClub: vi.fn(),
};

vi.mock("@/lib/auth", () => ({
  isAuthFailure: (result: unknown) => typeof result === "object" && result !== null && "response" in result,
  requireUser: (...args: unknown[]) => requireUserMock(...args),
}));
vi.mock("@/lib/club-war/supabase-repository", () => ({ supabaseClubWarRepository: repo }));

const { GET, POST } = await import("./route");
const { POST: RESPOND } = await import("./[id]/respond/route");
const { GET: RECORD } = await import("./record/route");
const { GET: CRON } = await import("../cron/club-wars/route");

const authed = () => requireUserMock.mockResolvedValue({ user: { id: "user-1", auth_user_id: "a1", deleted_at: null } });
const post = (body: unknown) =>
  new Request("https://example.com/api/club-wars", {
    method: "POST",
    headers: { authorization: "Bearer t" },
    body: typeof body === "string" ? body : JSON.stringify(body),
  });

const war = (overrides: Record<string, unknown> = {}) => ({
  id: "w1",
  status: "ended",
  challengeSentAt: new Date("2026-10-01T00:00:00Z"),
  acceptDeadlineAt: new Date("2026-10-02T00:00:00Z"),
  startedAt: new Date("2026-10-01T06:00:00Z"),
  endedAt: new Date("2026-10-03T06:00:00Z"),
  winnerClubId: "A",
  winReason: "participation_rate",
  clubs: [
    { clubId: "A", role: "inviter", inviteStatus: "accepted" },
    { clubId: "B", role: "invited", inviteStatus: "accepted" },
  ],
  ...overrides,
});

beforeEach(() => {
  vi.clearAllMocks();
});

describe("POST /api/club-wars", () => {
  it("passes auth failures through", async () => {
    requireUserMock.mockResolvedValueOnce({ response: Response.json({}, { status: 401 }) });
    expect((await POST(post({ invited_club_ids: ["B"] }))).status).toBe(401);
  });

  it("refuses every valid challenge as not_premium_club until T4.20 ships — and creates nothing", async () => {
    authed();
    repo.getMembership.mockResolvedValue({ clubId: "A", role: "owner" });
    repo.existingClubIds.mockResolvedValue(["B"]);
    const res = await POST(post({ invited_club_ids: ["B"] }));
    expect(res.status).toBe(403);
    expect(await res.json()).toEqual({ error: "not_premium_club" });
    expect(repo.createWar).not.toHaveBeenCalled();
  });

  it("rejects malformed JSON and bad invite lists with 400", async () => {
    authed();
    expect((await POST(post("{nope"))).status).toBe(400);
    expect((await POST(post({ invited_club_ids: [] }))).status).toBe(400);
  });

  it("403 for a caller without a club, 403 for a plain member", async () => {
    authed();
    repo.getMembership.mockResolvedValueOnce(null);
    expect((await POST(post({ invited_club_ids: ["B"] }))).status).toBe(403);
    repo.getMembership.mockResolvedValueOnce({ clubId: "A", role: "member" });
    const res = await POST(post({ invited_club_ids: ["B"] }));
    expect(await res.json()).toEqual({ error: "not_club_admin" });
  });
});

describe("GET /api/club-wars", () => {
  it("lists the caller's club's wars with a computed ends_at", async () => {
    authed();
    repo.getMembership.mockResolvedValue({ clubId: "A", role: "member" });
    repo.listWarsForClub.mockResolvedValue([war()]);
    const res = await GET(new Request("https://example.com/api/club-wars"));
    expect(res.status).toBe(200);
    const json = await res.json();
    expect(json.club_id).toBe("A");
    expect(json.wars[0]).toMatchObject({
      id: "w1",
      status: "ended",
      started_at: "2026-10-01T06:00:00.000Z",
      ends_at: "2026-10-03T06:00:00.000Z",
      winner_club_id: "A",
      clubs: [
        { club_id: "A", role: "inviter", invite_status: "accepted" },
        { club_id: "B", role: "invited", invite_status: "accepted" },
      ],
    });
  });

  it("403 when the caller isn't in a club", async () => {
    authed();
    repo.getMembership.mockResolvedValue(null);
    expect((await GET(new Request("https://example.com/api/club-wars"))).status).toBe(403);
  });
});

describe("POST /api/club-wars/:id/respond", () => {
  const respond = (body: unknown) =>
    RESPOND(
      new Request("https://example.com/api/club-wars/w1/respond", { method: "POST", body: JSON.stringify(body) }),
      { params: Promise.resolve({ id: "w1" }) }
    );

  it("400 when accept isn't a boolean", async () => {
    authed();
    expect((await respond({ accept: "yes" })).status).toBe(400);
  });

  it("404 for an unknown war", async () => {
    authed();
    repo.getWar.mockResolvedValue(null);
    expect((await respond({ accept: true })).status).toBe(404);
  });

  it("a decline dissolves the challenge", async () => {
    authed();
    repo.getWar.mockResolvedValue(
      war({
        status: "pending",
        startedAt: null,
        endedAt: null,
        winnerClubId: null,
        winReason: null,
        acceptDeadlineAt: new Date(Date.now() + 60_000),
        clubs: [
          { clubId: "A", role: "inviter", inviteStatus: "accepted" },
          { clubId: "B", role: "invited", inviteStatus: "pending" },
        ],
      })
    );
    repo.getMembership.mockResolvedValue({ clubId: "B", role: "owner" });
    repo.dissolveWar.mockResolvedValue(true);
    const res = await respond({ accept: false });
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ war_id: "w1", status: "dissolved" });
    expect(repo.recordResult).not.toHaveBeenCalled();
  });
});

describe("GET /api/club-wars/record", () => {
  it("counts only ended wars: wins, losses, net wins", async () => {
    authed();
    repo.getMembership.mockResolvedValue({ clubId: "A", role: "member" });
    repo.listWarsForClub.mockResolvedValue([
      war({ id: "w1", winnerClubId: "A" }),
      war({ id: "w2", winnerClubId: "B" }),
      war({ id: "w3", winnerClubId: null }),
      war({ id: "w4", status: "dissolved", winnerClubId: null }),
      war({ id: "w5", status: "active", winnerClubId: null }),
    ]);
    const res = await RECORD(new Request("https://example.com/api/club-wars/record"));
    expect(await res.json()).toEqual({ club_id: "A", wins: 1, losses: 2, net_wins: -1 });
  });
});

describe("GET /api/cron/club-wars", () => {
  it("rejects calls without the cron secret", async () => {
    const res = await CRON(new Request("https://example.com/api/cron/club-wars"));
    expect(res.status).toBe(401);
    expect(repo.listExpiredPendingWarIds).not.toHaveBeenCalled();
  });

  it("with CRON_SECRET unset, the literal 'Bearer undefined' is still rejected", async () => {
    const saved = process.env.CRON_SECRET;
    delete process.env.CRON_SECRET;
    try {
      const res = await CRON(
        new Request("https://example.com/api/cron/club-wars", { headers: { authorization: "Bearer undefined" } })
      );
      expect(res.status).toBe(401);
      expect(repo.listExpiredPendingWarIds).not.toHaveBeenCalled();
    } finally {
      if (saved !== undefined) process.env.CRON_SECRET = saved;
    }
  });

  it("dissolves expired challenges and finalizes due wars", async () => {
    vi.stubEnv("CRON_SECRET", "s3cret");
    repo.listExpiredPendingWarIds.mockResolvedValue(["w9"]);
    repo.dissolveWar.mockResolvedValue(true);
    repo.listActiveWarsStartedBefore.mockResolvedValue([]);
    const res = await CRON(
      new Request("https://example.com/api/cron/club-wars", { headers: { authorization: "Bearer s3cret" } })
    );
    expect(await res.json()).toEqual({ dissolved: ["w9"], ended: [], unresolved_ties: [] });
    vi.unstubAllEnvs();
  });
});
