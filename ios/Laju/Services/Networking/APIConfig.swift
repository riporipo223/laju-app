import Foundation

/// T2.14: the backend's own base URL (Next.js/Vercel, distinct from `SupabaseConfig`'s Supabase project
/// URL — Supabase Auth is the identity provider, this is the app's own API for runs/points/leaderboard).
/// Nothing in the app referenced this before T2.14; the sync queue is the first consumer.
enum APIConfig {
    static let baseURL = URL(string: "https://backend-eight-gules-56.vercel.app")!
}
