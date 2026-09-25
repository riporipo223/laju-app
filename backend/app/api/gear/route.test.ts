import { beforeEach, describe, expect, it, vi } from "vitest";

const requireUserMock = vi.fn();

// `.from("gear").insert(...).select(...).single()` — POST's insert.
const insertChain = {
  select: vi.fn(() => insertChain),
  single: vi.fn(
    (): Promise<{
      data: { id: string; brand: string; model: string | null; size: string | null; created_at: string } | null;
      error: { message: string } | null;
    }> => Promise.resolve({ data: null, error: null })
  ),
};
const insertMock = vi.fn((_row: unknown) => insertChain);

// `.from("gear").select(...).eq(...).order(...)` — GET's list query.
const listChain = {
  select: vi.fn(() => listChain),
  eq: vi.fn(() => listChain),
  order: vi.fn(
    (): Promise<{ data: unknown[] | null; error: { message: string } | null }> => Promise.resolve({ data: [], error: null })
  ),
};

vi.mock("@/lib/auth", () => ({
  isAuthFailure: (result: unknown) => typeof result === "object" && result !== null && "response" in result,
  requireUser: (...args: unknown[]) => requireUserMock(...args),
}));

vi.mock("@/lib/supabase", () => ({
  supabaseAdmin: {
    from: (table: string) => {
      if (table === "gear") return { insert: insertMock, select: listChain.select };
      throw new Error(`unexpected table: ${table}`);
    },
  },
}));

const { POST, GET } = await import("./route");

const completeUser = { id: "usr-1", auth_user_id: "auth-1", deleted_at: null };

function postRequest(body: unknown) {
  return new Request("https://example.com/api/gear", {
    method: "POST",
    headers: { authorization: "Bearer valid-jwt", "content-type": "application/json" },
    body: JSON.stringify(body),
  });
}

function getRequest() {
  return new Request("https://example.com/api/gear", { headers: { authorization: "Bearer valid-jwt" } });
}

describe("POST /api/gear", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("rejects unauthenticated requests", async () => {
    requireUserMock.mockResolvedValueOnce({ response: Response.json({}, { status: 401 }) });
    const res = await POST(postRequest({ brand: "Nike" }));
    expect(res.status).toBe(401);
    expect(insertMock).not.toHaveBeenCalled();
  });

  it("returns 400 when brand is missing", async () => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
    const res = await POST(postRequest({}));
    expect(res.status).toBe(400);
    expect(insertMock).not.toHaveBeenCalled();
  });

  it("returns 400 when brand is not in the v1 list", async () => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
    const res = await POST(postRequest({ brand: "Not A Real Brand" }));
    expect(res.status).toBe(400);
    expect(insertMock).not.toHaveBeenCalled();
  });

  it("returns 400 when model exceeds the max length", async () => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
    const res = await POST(postRequest({ brand: "Nike", model: "x".repeat(101) }));
    expect(res.status).toBe(400);
  });

  it("creates gear with brand only (model/size optional)", async () => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
    insertChain.single.mockResolvedValueOnce({
      data: { id: "gear-1", brand: "Nike", model: null, size: null, created_at: "2026-09-25T10:00:00Z" },
      error: null,
    });

    const res = await POST(postRequest({ brand: "Nike" }));
    expect(res.status).toBe(201);
    const json = await res.json();
    expect(json).toEqual({ gear_id: "gear-1", brand: "Nike", model: null, size: null, created_at: "2026-09-25T10:00:00Z" });

    const insertedRow = insertMock.mock.calls.at(-1)?.[0] as { user_id: string; brand: string };
    expect(insertedRow).toEqual({ user_id: "usr-1", brand: "Nike", model: null, size: null });
  });

  it("creates gear with brand, model and size, trimmed", async () => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
    insertChain.single.mockResolvedValueOnce({
      data: { id: "gear-2", brand: "Nike", model: "AirMax 95", size: "42", created_at: "2026-09-25T10:00:00Z" },
      error: null,
    });

    const res = await POST(postRequest({ brand: "Nike", model: "  AirMax 95  ", size: " 42 " }));
    expect(res.status).toBe(201);
    const insertedRow = insertMock.mock.calls.at(-1)?.[0] as { model: string; size: string };
    expect(insertedRow.model).toBe("AirMax 95");
    expect(insertedRow.size).toBe("42");
  });

  it("returns 500 when the insert fails", async () => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
    insertChain.single.mockResolvedValueOnce({ data: null, error: { message: "db error" } });
    const res = await POST(postRequest({ brand: "Nike" }));
    expect(res.status).toBe(500);
  });
});

describe("GET /api/gear", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("rejects unauthenticated requests", async () => {
    requireUserMock.mockResolvedValueOnce({ response: Response.json({}, { status: 401 }) });
    const res = await GET(getRequest());
    expect(res.status).toBe(401);
  });

  it("returns the caller's own gear list, scoped by user_id", async () => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
    listChain.order.mockResolvedValueOnce({
      data: [
        { id: "gear-1", brand: "Nike", model: "AirMax 95", size: "42", created_at: "2026-09-25T10:00:00Z" },
        { id: "gear-2", brand: "Hoka", model: null, size: null, created_at: "2026-09-25T11:00:00Z" },
      ],
      error: null,
    });

    const res = await GET(getRequest());
    expect(res.status).toBe(200);
    const json = await res.json();
    expect(json).toEqual({
      gear: [
        { gear_id: "gear-1", brand: "Nike", model: "AirMax 95", size: "42", created_at: "2026-09-25T10:00:00Z" },
        { gear_id: "gear-2", brand: "Hoka", model: null, size: null, created_at: "2026-09-25T11:00:00Z" },
      ],
    });
    expect(listChain.eq).toHaveBeenCalledWith("user_id", "usr-1");
  });

  it("returns 500 when the list query fails", async () => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
    listChain.order.mockResolvedValueOnce({ data: null, error: { message: "db error" } });
    const res = await GET(getRequest());
    expect(res.status).toBe(500);
  });
});
