import Foundation

/// `POST /api/profile/complete` (database-api-spec.md §2.1, T2.4). `display_name` is left out on purpose: the server
/// defaults it to the username, and there is no separate field for it in the onboarding step.
struct CompleteProfileRequest: Encodable, Equatable, Sendable {
    let username: String
    let regionKecamatan: String
    let regionKabupatenKota: String
    let regionProvinsi: String

    enum CodingKeys: String, CodingKey {
        case username
        case regionKecamatan = "region_kecamatan"
        case regionKabupatenKota = "region_kabupaten_kota"
        case regionProvinsi = "region_provinsi"
    }
}

/// The body of the server's "signed in, but no profile row yet" 401 — its `code` is what tells the app to show the
/// profile step instead of treating the 401 as a broken session.
struct AuthErrorBody: Decodable {
    let code: String?
}
