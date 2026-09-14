import SwiftUI

/// Run Summary's "reward moment" (design-notes.md §4) — a burst/explosion from one point (like a
/// transaction-success moment), NOT falling-from-top confetti: particles launch outward at high initial
/// speed in every direction, gravity curves them down, then they fade. ~1.5s, never loops, `accent` lime +
/// white + `premium` violet only (design-notes.md's palette, not default rainbow).
struct ConfettiBurstView: View {
    let isActive: Bool
    /// Where the burst originates, in unit coordinates (0...1) of this view's own frame — deliberately upper
    /// area, not dead-center, so the burst and its fall stay clear of the stat numbers below it.
    var origin: UnitPoint = .init(x: 0.5, y: 0.28)

    private let duration: Double = 1.6
    private let gravity: Double = 900

    @State private var particles: [Particle] = []
    @State private var startTime: Date?

    private struct Particle {
        let angle: Double
        let speed: Double
        let size: CGFloat
        let color: Color
        let rotationSpeed: Double
        let isRound: Bool
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                guard let startTime else { return }
                let elapsed = timeline.date.timeIntervalSince(startTime)
                guard elapsed >= 0, elapsed <= duration else { return }
                let center = CGPoint(x: size.width * origin.x, y: size.height * origin.y)
                let fadeStart = duration * 0.6
                let opacity = elapsed > fadeStart ? max(0, 1 - (elapsed - fadeStart) / (duration - fadeStart)) : 1

                for particle in particles {
                    let particleX = center.x + CGFloat(cos(particle.angle) * particle.speed * elapsed)
                    let particleY = center.y + CGFloat(
                        sin(particle.angle) * particle.speed * elapsed + 0.5 * gravity * elapsed * elapsed
                    )

                    var particleContext = context
                    particleContext.opacity = opacity
                    particleContext.translateBy(x: particleX, y: particleY)
                    particleContext.rotate(by: .degrees(particle.rotationSpeed * elapsed))

                    let half = particle.size / 2
                    let rect = CGRect(
                        x: -half,
                        y: -half,
                        width: particle.size,
                        height: particle.isRound ? particle.size : particle.size * 0.4
                    )
                    let path = particle.isRound ? Path(ellipseIn: rect) : Path(rect)
                    particleContext.fill(path, with: .color(particle.color))
                }
            }
        }
        .allowsHitTesting(false)
        .onChange(of: isActive) { active in
            guard active else { return }
            particles = Self.makeParticles()
            startTime = Date()
        }
        .onAppear {
            guard isActive else { return }
            particles = Self.makeParticles()
            startTime = Date()
        }
    }

    private static func makeParticles() -> [Particle] {
        let palette: [Color] = [LajuColor.accent, .white, LajuColor.premium]
        return (0 ..< 32).map { _ in
            Particle(
                angle: .random(in: 0 ..< (2 * .pi)),
                speed: .random(in: 260 ... 480),
                size: .random(in: 5 ... 11),
                color: palette.randomElement() ?? LajuColor.accent,
                rotationSpeed: .random(in: -360 ... 360),
                isRound: Bool.random()
            )
        }
    }
}
