@testable import Laju
import XCTest

final class RunStatusCopyTests: XCTestCase {
    // MARK: - DoD: status-appropriate copy for flagged (low/high differentiated), approved, rejected

    func testFlaggedLowAndHighHaveDifferentCopy() throws {
        let low = try XCTUnwrap(RunStatusCopy.make(serverStatus: "flagged", flagConfidence: "low", anomalyFlags: []))
        let high = try XCTUnwrap(RunStatusCopy.make(serverStatus: "flagged", flagConfidence: "high", anomalyFlags: []))

        XCTAssertEqual(low.headline, "Poin tertahan sementara, otomatis diproses dalam ≤48 jam")
        XCTAssertEqual(high.headline, "Poin ditahan, perlu direview manual, bisa makan waktu lebih lama")
        XCTAssertNotEqual(low.headline, high.headline)
    }

    func testApprovedCopy() throws {
        let copy = try XCTUnwrap(RunStatusCopy.make(serverStatus: "approved", flagConfidence: "low", anomalyFlags: []))
        XCTAssertEqual(copy.headline, "Poin kamu sudah disetujui dan masuk leaderboard")
    }

    func testRejectedShowsPointsCancelledAndTheSpecificReasons() throws {
        let copy = try XCTUnwrap(RunStatusCopy.make(
            serverStatus: "rejected",
            flagConfidence: "high",
            anomalyFlags: ["pace_cap_exceeded", "gps_speed_jump_segment_3"]
        ))
        XCTAssertEqual(copy.headline, "Poin dibatalkan")
        XCTAssertEqual(copy.reasons, [
            "Pace rata-rata kamu terlalu cepat untuk lari manusia",
            "Lari kamu kedeteksi lompat lokasi tiba-tiba"
        ])
    }

    func testNoCopyForUnsyncedOrValidatedRuns() {
        XCTAssertNil(RunStatusCopy.make(serverStatus: nil, flagConfidence: nil, anomalyFlags: []))
        XCTAssertNil(RunStatusCopy.make(serverStatus: "validated", flagConfidence: nil, anomalyFlags: []))
    }

    // MARK: - DoD: raw anomalyFlags codes are never shown — always translated

    func testEveryKnownFlagFamilyTranslatesAndNeverLeaksTheRawCode() {
        let flags = [
            "pace_cap_exceeded",
            "gps_speed_jump_segment_3",
            "distance_duration_sanity_segment_12",
            "elevation_anomaly_segment_0",
            "some_future_flag_v2"
        ]
        let messages = RunStatusCopy.translate(flags)

        XCTAssertEqual(messages.count, 5)
        for message in messages {
            for flag in flags {
                XCTAssertFalse(message.contains(flag), "raw code leaked into user-facing copy: \(flag)")
            }
            XCTAssertFalse(message.contains("_"), "snake_case must never reach the user: \(message)")
        }
    }

    func testUnknownFlagFallsBackToAGenericReason() {
        XCTAssertEqual(RunStatusCopy.translate(["totally_new_check"]), ["Ada pola lari yang tidak biasa"])
    }

    func testMultipleSegmentFlagsOfOneFamilyCollapseToOneReason() {
        let messages = RunStatusCopy.translate([
            "gps_speed_jump_segment_1", "gps_speed_jump_segment_4", "gps_speed_jump_segment_9"
        ])
        XCTAssertEqual(messages, ["Lari kamu kedeteksi lompat lokasi tiba-tiba"])
    }

    // MARK: - DoD: a background resolution changes the copy on the same stored row

    func testCopyFollowsTheStoredRowThroughAFlaggedToApprovedResolution() throws {
        let context = PersistenceController(inMemory: true).container.viewContext
        let run = Run(context: context)
        run.id = UUID()
        run.startedAt = Date()
        run.serverStatus = "flagged"
        run.flagConfidence = "low"
        run.anomalyFlags = try JSONEncoder().encode(["pace_cap_exceeded"])

        let before = try XCTUnwrap(run.statusCopy)
        XCTAssertEqual(before.headline, "Poin tertahan sementara, otomatis diproses dalam ≤48 jam")
        XCTAssertEqual(before.reasons, ["Pace rata-rata kamu terlalu cepat untuk lari manusia"])

        // What `ReconciliationService.apply` (T2.14d) writes when the cron auto-approves the run.
        run.serverStatus = "approved"

        let after = try XCTUnwrap(run.statusCopy)
        XCTAssertEqual(after.headline, "Poin kamu sudah disetujui dan masuk leaderboard")
    }
}
