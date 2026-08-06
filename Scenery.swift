//
//  Scenery.swift
//  Hungry Frog
//
//  The parts every character's play backdrop is built from: the strip of land
//  the lounger stands on, and the plants, animals and weather that dress the
//  scene around it. The ten habitats themselves live in CharacterScenes.swift.
//
//  Nothing in here knows which character it belongs to. A scene picks the
//  pieces it needs, sizes them in scenery units and paints them in its own
//  palette, which is what lets a pond, a savannah and a seabed share one set
//  of plants without any of them looking borrowed.
//

import SwiftUI

// MARK: - Scale

enum Scenery {
    /// One scenery unit: the measure every piece of decor is sized in, so a
    /// scene keeps its proportions from the narrowest phone to the widest pad
    /// without each plant needing a phone size and a pad size of its own.
    /// Landscape phones land close to 1 and a pad close to 1.35 — the same
    /// ratio the hand-tuned pond used before this existed.
    static func unit(for size: CGSize) -> CGFloat {
        max(0.72, min(size.height / 400, size.width / 900))
    }
}

// MARK: - Motion
//
// Scenery moves; the character never does. Every movement here is a single
// SwiftUI animation between two fixed states, started once when the scene
// appears, so the render server owns it from then on: no view body is
// evaluated a second time and the swarm's own frame budget is untouched.
//
// A scene keeps everything that moves in one thin layer of its own, outside
// the flattened still artwork, and leaves that layer out entirely when the
// player has asked for reduced motion.
//
// ORDER MATTERS. Anything below that rotates or scales — `scenerySway`,
// `sceneryGlow`, `sceneryRipple`, a spinning `sceneryDrift` — must be applied
// to a *sized* view, before `.position(…)`. `.position` hands back a view that
// fills the whole scene, so a rotation applied after it takes the scene's
// centre as its anchor: a flower asked to lean three degrees in a breeze
// instead swings through an arc the width of the screen. `sceneryBob` and a
// plain `sceneryDrift` are only translations and are safe either way; the same
// trap catches a decorative `.rotationEffect` on a still prop, which silently
// moves it somewhere else entirely.

private struct SwayEffect: ViewModifier {
    let degrees: Double
    let period: Double
    let delay: Double
    let anchor: UnitPoint
    @State private var forward = false

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(forward ? degrees : -degrees), anchor: anchor)
            .animation(.easeInOut(duration: period).delay(delay)
                .repeatForever(autoreverses: true), value: forward)
            .onAppear { forward = true }
    }
}

private struct BobEffect: ViewModifier {
    let dx: CGFloat
    let dy: CGFloat
    let period: Double
    let delay: Double
    @State private var forward = false

    func body(content: Content) -> some View {
        content
            .offset(x: forward ? dx : -dx, y: forward ? dy : -dy)
            .animation(.easeInOut(duration: period).delay(delay)
                .repeatForever(autoreverses: true), value: forward)
            .onAppear { forward = true }
    }
}

/// One-way travel that never eases and never reverses: the piece starts out of
/// sight, crosses the scene and is out of sight again by the time the loop
/// restarts, so the jump back to the beginning is never on screen.
private struct DriftEffect: ViewModifier {
    let dx: CGFloat
    let dy: CGFloat
    let spin: Double
    let period: Double
    let delay: Double
    @State private var moved = false

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(moved ? spin : 0))
            .offset(x: moved ? dx : 0, y: moved ? dy : 0)
            .animation(.linear(duration: period).delay(delay)
                .repeatForever(autoreverses: false), value: moved)
            .onAppear { moved = true }
    }
}

private struct GlowEffect: ViewModifier {
    let low: Double
    let period: Double
    let delay: Double
    @State private var forward = false

    func body(content: Content) -> some View {
        content
            .opacity(forward ? 1 : low)
            .scaleEffect(forward ? 1.05 : 1)
            .animation(.easeInOut(duration: period).delay(delay)
                .repeatForever(autoreverses: true), value: forward)
            .onAppear { forward = true }
    }
}

/// A ring spreading out on water and fading as it goes. It ends invisible, so
/// the restart at the top of every cycle is never seen.
private struct RippleEffect: ViewModifier {
    let period: Double
    let delay: Double
    @State private var open = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(open ? 1.9 : 0.35)
            .opacity(open ? 0 : 1)
            .animation(.easeOut(duration: period).delay(delay)
                .repeatForever(autoreverses: false), value: open)
            .onAppear { open = true }
    }
}

private struct FlapEffect: ViewModifier {
    let period: Double
    let delay: Double
    @State private var forward = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(x: forward ? 0.42 : 1, y: 1, anchor: .center)
            .animation(.easeInOut(duration: period).delay(delay)
                .repeatForever(autoreverses: true), value: forward)
            .onAppear { forward = true }
    }
}

extension View {
    /// Leans back and forth about a fixed anchor: stems in a breeze, a palm
    /// crown, kelp in a current.
    func scenerySway(_ degrees: Double, period: Double, delay: Double = 0,
                     anchor: UnitPoint = .bottom) -> some View {
        modifier(SwayEffect(degrees: degrees, period: period, delay: delay, anchor: anchor))
    }

    /// Rides up and down on the spot: anything floating on water.
    func sceneryBob(dx: CGFloat = 0, dy: CGFloat, period: Double, delay: Double = 0) -> some View {
        modifier(BobEffect(dx: dx, dy: dy, period: period, delay: delay))
    }

    /// Crosses the scene once per period and starts over out of sight.
    func sceneryDrift(dx: CGFloat = 0, dy: CGFloat = 0, spin: Double = 0,
                      period: Double, delay: Double = 0) -> some View {
        modifier(DriftEffect(dx: dx, dy: dy, spin: spin, period: period, delay: delay))
    }

    /// Breathes in brightness: a sun, a firefly, a shaft of light.
    func sceneryGlow(low: Double = 0.7, period: Double, delay: Double = 0) -> some View {
        modifier(GlowEffect(low: low, period: period, delay: delay))
    }

    /// Squeezes side to side, which is all a pair of wings needs to read as
    /// flapping at this size.
    func sceneryFlap(period: Double, delay: Double = 0) -> some View {
        modifier(FlapEffect(period: period, delay: delay))
    }

    /// Spreads out and fades, like something small breaking the surface.
    func sceneryRipple(period: Double, delay: Double = 0) -> some View {
        modifier(RippleEffect(period: period, delay: delay))
    }
}

// MARK: - Shapes

struct SceneryTriangleShape: Shape {
    /// How far the apex sits from the left edge, as a share of the width.
    var apex: CGFloat = 0.5

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * apex, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// A bank of ground: a broad crown that flares out to the full width at the
/// bottom. Used for every piece of land a lounger stands on, and for rocks.
struct SceneryMoundShape: Shape {
    /// The share of the width the crown runs flat across before it falls away.
    var crown: CGFloat = 0.34

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addCurve(to: CGPoint(x: rect.midX - w * crown * 0.5, y: rect.minY),
                      control1: CGPoint(x: rect.minX + w * 0.07, y: rect.maxY - h * 0.44),
                      control2: CGPoint(x: rect.minX + w * 0.21, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX + w * crown * 0.5, y: rect.minY))
        path.addCurve(to: CGPoint(x: rect.maxX, y: rect.maxY),
                      control1: CGPoint(x: rect.maxX - w * 0.18, y: rect.minY),
                      control2: CGPoint(x: rect.maxX - w * 0.06, y: rect.maxY - h * 0.38))
        path.closeSubpath()
        return path
    }
}

/// An ellipse with a wedge taken out of it: a lily pad, seen from the bank.
///
/// The wedge is turned inside the shape's own circle, before the ellipse is
/// flattened. Rotating the finished pad instead would tilt the flattening with
/// it, and a pad lying on water does not tilt — it only ever turns about the
/// spot it floats on.
struct SceneryPadShape: Shape {
    /// Width of the wedge, in degrees.
    var notch: Double = 34
    /// Which way the wedge faces, in degrees clockwise from pointing right.
    var notchAngle: Double = 0

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: .zero)
        path.addArc(center: .zero, radius: 0.5,
                    startAngle: .degrees(notchAngle + notch * 0.5),
                    endAngle: .degrees(notchAngle + 360 - notch * 0.5),
                    clockwise: false)
        path.closeSubpath()
        return path.applying(CGAffineTransform(a: rect.width, b: 0, c: 0,
                                              d: rect.height,
                                              tx: rect.midX, ty: rect.midY))
    }
}

/// A slice with its point at the bottom, opening upwards: shells and fans.
struct SceneryPieShape: Shape {
    var spread: Double = 158

    func path(in rect: CGRect) -> Path {
        let apex = CGPoint(x: rect.midX, y: rect.maxY)
        var path = Path()
        path.move(to: apex)
        path.addArc(center: apex, radius: rect.height,
                    startAngle: .degrees(-90 - spread * 0.5),
                    endAngle: .degrees(-90 + spread * 0.5),
                    clockwise: false)
        path.closeSubpath()
        return path
    }
}

struct SceneryStarShape: Shape {
    var points: Int = 5
    var innerRatio: CGFloat = 0.44

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) * 0.5
        let inner = outer * innerRatio
        var path = Path()
        for step in 0..<(points * 2) {
            let angle = -Double.pi / 2 + Double(step) * .pi / Double(points)
            let radius = step.isMultiple(of: 2) ? outer : inner
            let point = CGPoint(x: center.x + CGFloat(cos(angle)) * radius,
                                y: center.y + CGFloat(sin(angle)) * radius)
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

/// A pail: wider at the rim than at the base.
struct SceneryPailShape: Shape {
    /// How much narrower the base is than the rim.
    var taper: CGFloat = 0.24

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * taper * 0.5, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX + rect.width * taper * 0.5,
                                      y: rect.maxY),
                          control: CGPoint(x: rect.midX, y: rect.maxY + rect.height * 0.12))
        path.closeSubpath()
        return path
    }
}

/// A palm frond: rooted at the left edge, arching over and dipping at the tip.
struct SceneryFrondShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY),
                          control: CGPoint(x: rect.midX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.midY),
                          control: CGPoint(x: rect.midX + rect.width * 0.1,
                                           y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// A pointed oval: leaves, fronds, petals of the longer kind.
struct SceneryLeafShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.midY),
                          control: CGPoint(x: rect.midX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.midY),
                          control: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Sky

struct SceneryCloud: View {
    var width: CGFloat
    var tint: Color = .white
    var opacity: Double = 0.72
    var glows: Bool = true

    var body: some View {
        ZStack {
            Capsule().frame(width: width, height: width * 0.30).offset(y: width * 0.095)
            Circle().frame(width: width * 0.47).offset(x: -width * 0.23)
            Circle().frame(width: width * 0.59).offset(x: width * 0.12, y: -width * 0.06)
            Circle().frame(width: width * 0.38).offset(x: width * 0.38, y: width * 0.05)
        }
        .foregroundStyle(tint.opacity(opacity))
        .shadow(color: glows ? tint.opacity(0.26) : .clear, radius: width * 0.08)
        .frame(width: width * 1.45, height: width * 0.75)
    }
}

struct ScenerySun: View {
    var diameter: CGFloat
    var core: Color
    var halo: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(halo.opacity(0.34))
                .frame(width: diameter * 2.3, height: diameter * 2.3)
                .blur(radius: diameter * 0.34)
            Circle()
                .fill(core)
                .frame(width: diameter, height: diameter)
                .blur(radius: 1)
        }
        .frame(width: diameter * 2.3, height: diameter * 2.3)
    }
}

/// Curtains of light for the polar sky: a few wide, blurred bands leaning
/// against each other.
struct SceneryAurora: View {
    var width: CGFloat
    var height: CGFloat
    var colors: [Color]

    var body: some View {
        ZStack {
            ForEach(Array(colors.enumerated()), id: \.offset) { index, color in
                Capsule()
                    .fill(LinearGradient(colors: [color.opacity(0), color, color.opacity(0)],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: width * (1 - CGFloat(index) * 0.14),
                           height: height * (0.30 - CGFloat(index) * 0.05))
                    .rotationEffect(.degrees(Double(index) * 7 - 9))
                    .offset(x: CGFloat(index) * width * 0.05,
                            y: CGFloat(index) * height * 0.24 - height * 0.2)
                    .blur(radius: height * 0.09)
            }
        }
        .frame(width: width, height: height)
    }
}

/// A gull, at the size a gull is on a horizon: two curved strokes.
struct SceneryBird: View {
    var width: CGFloat
    var color: Color

    var body: some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: width * 0.22))
            path.addQuadCurve(to: CGPoint(x: width * 0.5, y: width * 0.10),
                              control: CGPoint(x: width * 0.26, y: -width * 0.06))
            path.addQuadCurve(to: CGPoint(x: width, y: width * 0.22),
                              control: CGPoint(x: width * 0.74, y: -width * 0.06))
        }
        .stroke(color, style: StrokeStyle(lineWidth: max(1.2, width * 0.075),
                                          lineCap: .round))
        .frame(width: width, height: width * 0.34)
    }
}

struct SceneryButterfly: View {
    var width: CGFloat
    var wing: Color
    var wingDeep: Color
    var flaps: Bool = true

    var body: some View {
        HStack(spacing: width * 0.06) {
            wingPair.scaleEffect(x: -1)
            wingPair
        }
        .frame(width: width, height: width * 0.8)
        .modifier(FlapWrapper(active: flaps, period: 0.42))
    }

    private var wingPair: some View {
        ZStack(alignment: .bottomLeading) {
            Ellipse()
                .fill(wing)
                .frame(width: width * 0.44, height: width * 0.42)
                .offset(y: -width * 0.24)
            Ellipse()
                .fill(wingDeep)
                .frame(width: width * 0.32, height: width * 0.30)
        }
        .frame(width: width * 0.46, height: width * 0.7, alignment: .bottomLeading)
    }
}

/// Applies the flap only when a scene asked for it, so the same artwork can be
/// dropped into a still layer without dragging an animation along with it.
private struct FlapWrapper: ViewModifier {
    let active: Bool
    let period: Double

    func body(content: Content) -> some View {
        if active {
            content.sceneryFlap(period: period)
        } else {
            content
        }
    }
}

struct SceneryDragonfly: View {
    var width: CGFloat
    var bodyColor: Color
    var wing: Color

    var body: some View {
        ZStack {
            Capsule()
                .fill(bodyColor)
                .frame(width: width, height: max(2, width * 0.09))
            Ellipse()
                .fill(wing.opacity(0.55))
                .frame(width: width * 0.46, height: width * 0.14)
                .offset(x: -width * 0.04, y: -width * 0.11)
            Ellipse()
                .fill(wing.opacity(0.55))
                .frame(width: width * 0.46, height: width * 0.14)
                .offset(x: -width * 0.04, y: width * 0.11)
            Circle()
                .fill(bodyColor)
                .frame(width: width * 0.15, height: width * 0.15)
                .offset(x: -width * 0.44)
        }
        .frame(width: width * 1.1, height: width * 0.4)
    }
}

/// A fish. It is painted facing left — eye at the leading edge, tail trailing
/// behind it — so one crossing the scene to the right has to be turned round.
/// That is what `swimsRight` is for: the mirror is applied here, to the fish's
/// own frame, rather than left to the caller to remember and to get the wrong
/// way round.
struct SceneryFish: View {
    var length: CGFloat
    var color: Color
    var belly: Color
    /// Set this to match the direction the fish is actually being sent.
    var swimsRight: Bool = false

    var body: some View {
        artwork.scaleEffect(x: swimsRight ? -1 : 1)
    }

    private var artwork: some View {
        ZStack {
            SceneryTriangleShape(apex: 0)
                .fill(color)
                .frame(width: length * 0.30, height: length * 0.36)
                .rotationEffect(.degrees(-90))
                .offset(x: length * 0.38)
            Ellipse()
                .fill(LinearGradient(colors: [color, belly],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: length * 0.74, height: length * 0.40)
            Circle()
                .fill(Color.black.opacity(0.62))
                .frame(width: max(1.5, length * 0.07))
                .offset(x: -length * 0.24, y: -length * 0.04)
        }
        .frame(width: length, height: length * 0.44)
    }
}

struct SceneryBubble: View {
    var diameter: CGFloat
    var color: Color = .white

    var body: some View {
        Circle()
            .strokeBorder(color.opacity(0.55), lineWidth: max(1, diameter * 0.12))
            .background(Circle().fill(color.opacity(0.14)))
            .overlay(alignment: .topLeading) {
                Circle()
                    .fill(color.opacity(0.7))
                    .frame(width: diameter * 0.22, height: diameter * 0.22)
                    .padding(diameter * 0.16)
            }
            .frame(width: diameter, height: diameter)
    }
}

struct SceneryFlake: View {
    var diameter: CGFloat

    var body: some View {
        Circle()
            .fill(Color.white.opacity(0.85))
            .frame(width: diameter, height: diameter)
            .blur(radius: diameter * 0.12)
    }
}

// MARK: - Ground

/// The piece of ground a lounger stands on. Every scene puts one of these
/// under the character: a bank with a broad, level crown, a lit top edge and
/// a rim where it meets whatever surrounds it.
struct SceneryGroundPatch: View {
    var width: CGFloat
    var height: CGFloat
    var crownColor: Color
    var earthColor: Color
    var rimColor: Color
    var crownShare: CGFloat = 0.60

    var body: some View {
        ZStack(alignment: .top) {
            // The crown colour holds most of the way down and the earth only
            // turns up at the foot. Ramped evenly instead, a bank deep enough
            // to stand a lounger on reads as a slab of soil across the screen.
            SceneryMoundShape(crown: crownShare)
                .fill(LinearGradient(stops: [.init(color: crownColor, location: 0),
                                             .init(color: crownColor, location: 0.46),
                                             .init(color: earthColor, location: 1)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: width, height: height)

            // A lighter lip along the crown itself. Kept narrow: run wide and
            // blurred it stops reading as an edge and starts reading as a
            // spotlight pointed at the lounger.
            Ellipse()
                .fill(rimColor.opacity(0.85))
                .frame(width: width * (crownShare + 0.15), height: height * 0.10)
                .blur(radius: max(1, height * 0.02))
                .offset(y: -height * 0.03)

            // And the shoulders falling away either side of it.
            SceneryMoundShape(crown: crownShare)
                .stroke(Color.black.opacity(0.06),
                        lineWidth: max(1, height * 0.05))
                .frame(width: width, height: height)
        }
        .frame(width: width, height: height, alignment: .top)
    }
}

/// A boulder: the top half of an ellipse, so it sits on the ground on a flat
/// base and keeps a rounded back instead of the ridge a mound shape gives it.
struct SceneryRock: View {
    var width: CGFloat
    var height: CGFloat
    var color: Color
    var light: Color

    var body: some View {
        ZStack(alignment: .bottom) {
            Ellipse()
                .fill(LinearGradient(colors: [light, color],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: width, height: height * 2)
                .offset(y: height)

            Ellipse()
                .fill(color.opacity(0.55))
                .frame(width: width * 0.42, height: height * 1.1)
                .offset(x: width * 0.22, y: height * 0.5)
                .blur(radius: max(1.5, height * 0.12))

            Ellipse()
                .fill(light.opacity(0.6))
                .frame(width: width * 0.3, height: height * 0.7)
                .offset(x: -width * 0.16, y: height * 0.4)
                .blur(radius: max(1.5, height * 0.14))
        }
        .frame(width: width, height: height, alignment: .bottom)
        .clipped()
    }
}

/// A fan of blades springing from one point: grass, reeds, sedge, a fern.
struct SceneryTuft: View {
    var width: CGFloat
    var height: CGFloat
    var color: Color
    var light: Color
    var blades: Int = 9

    var body: some View {
        ZStack(alignment: .bottom) {
            ForEach(0..<blades, id: \.self) { index in
                // Blades alternate either side of the middle rather than
                // sweeping across it, so a tuft never reads as an arrowhead.
                let step = Double((index + 1) / 2) / Double(max(1, blades / 2))
                let spread = index.isMultiple(of: 2) ? -step : step
                Capsule()
                    .fill(index.isMultiple(of: 3) ? light : color)
                    .frame(width: max(1.4, width * 0.055),
                           height: height * (1 - CGFloat(abs(spread)) * 0.42))
                    .rotationEffect(.degrees(spread * 28 + Double(index % 3) * 2),
                                    anchor: .bottom)
            }
        }
        .frame(width: width, height: height, alignment: .bottom)
    }
}

/// A fern: leaf blades instead of grass blades, arching out low and wide.
struct SceneryFern: View {
    var width: CGFloat
    var height: CGFloat
    var color: Color
    var light: Color

    var body: some View {
        ZStack(alignment: .bottom) {
            ForEach(0..<5, id: \.self) { index in
                let spread = Double(index) / 4 * 2 - 1
                SceneryLeafShape()
                    .fill(index.isMultiple(of: 2) ? color : light)
                    .frame(width: height * (1 - CGFloat(abs(spread)) * 0.26),
                           height: height * 0.26)
                    .offset(x: height * 0.5 * (1 - CGFloat(abs(spread)) * 0.26))
                    .rotationEffect(.degrees(spread * 52 - 90), anchor: .center)
            }
        }
        .frame(width: width, height: height, alignment: .bottom)
    }
}

// MARK: - Plants
//
// Each plant is drawn as one piece, in its own coordinates, with whatever sits
// on the tip placed against the tip itself. Leaning a plant then leans all of
// it: the flower head and the cattail's brown club travel with the stem they
// grow on instead of sliding off it.

/// A ring of petals around a centre. The petals are rotated around the
/// bloom's own middle, so the head stays a head at any size.
struct SceneryBloom: View {
    var diameter: CGFloat
    var petals: Int = 6
    var petalColor: Color
    var coreColor: Color
    var petalRatio: CGFloat = 0.36

    var body: some View {
        ZStack {
            ForEach(0..<petals, id: \.self) { index in
                Ellipse()
                    .fill(petalColor)
                    .frame(width: diameter * petalRatio, height: diameter * 0.60)
                    .offset(y: -diameter * 0.19)
                    .rotationEffect(.degrees(Double(index) * 360 / Double(petals)))
            }
            Circle()
                .fill(coreColor)
                .frame(width: diameter * 0.32, height: diameter * 0.32)
        }
        .frame(width: diameter, height: diameter)
    }
}

/// A flowering plant: a stem, one pair of leaves growing out of it and a bloom
/// resting on the tip.
struct SceneryFlowerPlant: View {
    var height: CGFloat
    var stemColor: Color
    var leafColor: Color
    var petalColor: Color
    var coreColor: Color
    var petals: Int = 6
    var lean: Double = 0

    var body: some View {
        let stemWidth = max(2, height * 0.045)
        let bloom = height * 0.32
        let leaf = height * 0.30

        ZStack(alignment: .bottom) {
            Capsule()
                .fill(stemColor)
                .frame(width: stemWidth, height: height - bloom * 0.44)

            SceneryLeafShape()
                .fill(leafColor)
                .frame(width: leaf, height: leaf * 0.40)
                .rotationEffect(.degrees(-30), anchor: .leading)
                .offset(x: leaf * 0.5 + stemWidth * 0.3, y: -height * 0.34)

            SceneryLeafShape()
                .fill(leafColor)
                .frame(width: leaf * 0.86, height: leaf * 0.36)
                .rotationEffect(.degrees(30), anchor: .trailing)
                .offset(x: -(leaf * 0.43 + stemWidth * 0.3), y: -height * 0.50)

            SceneryBloom(diameter: bloom, petals: petals,
                         petalColor: petalColor, coreColor: coreColor)
                .offset(y: -(height - bloom))
        }
        .frame(width: height * 0.7, height: height, alignment: .bottom)
        .rotationEffect(.degrees(lean), anchor: .bottom)
    }
}

/// A cattail: the brown club sits on the tip of its own stem, and the whole
/// plant leans as one.
struct SceneryCattail: View {
    var height: CGFloat
    var stemColor: Color
    var clubColor: Color
    var lean: Double = 0

    var body: some View {
        let stemWidth = max(2, height * 0.052)
        let clubHeight = height * 0.27
        let clubWidth = clubHeight * 0.44

        ZStack(alignment: .bottom) {
            Capsule()
                .fill(stemColor)
                .frame(width: stemWidth, height: height)

            Capsule()
                .fill(stemColor)
                .frame(width: stemWidth * 0.6, height: clubHeight * 0.55)
                .offset(y: -(height + clubHeight * 0.32))

            Capsule()
                .fill(LinearGradient(colors: [clubColor.opacity(0.82), clubColor],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: clubWidth, height: clubHeight)
                .offset(y: -(height - clubHeight))

            SceneryLeafShape()
                .fill(stemColor.opacity(0.9))
                .frame(width: height * 0.44, height: height * 0.09)
                .rotationEffect(.degrees(-58), anchor: .leading)
                .offset(x: height * 0.22, y: -height * 0.26)
        }
        .frame(width: max(clubWidth, stemWidth), height: height, alignment: .bottom)
        .rotationEffect(.degrees(lean), anchor: .bottom)
    }
}

struct SceneryLilyPad: View {
    var width: CGFloat
    var height: CGFloat
    var color: Color
    var deepColor: Color
    var notchAngle: Double = 0

    var body: some View {
        SceneryPadShape(notchAngle: notchAngle)
            .fill(LinearGradient(colors: [color, deepColor],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay {
                SceneryPadShape(notchAngle: notchAngle)
                    .stroke(deepColor.opacity(0.5), lineWidth: 1)
            }
            .overlay {
                ForEach(0..<5, id: \.self) { index in
                    Capsule()
                        .fill(Color.white.opacity(0.16))
                        .frame(width: width * 0.42, height: max(1, height * 0.035))
                        .offset(x: width * 0.21)
                        .rotationEffect(.degrees(Double(index) * 58 + 29))
                }
            }
            .overlay(alignment: .topLeading) {
                Ellipse()
                    .fill(Color.white.opacity(0.30))
                    .frame(width: width * 0.16, height: height * 0.16)
                    .padding(.leading, width * 0.22)
                    .padding(.top, height * 0.2)
            }
            .frame(width: width, height: height)
            .shadow(color: .black.opacity(0.14), radius: 3, y: 2)
    }
}

/// A water lily sitting on the surface: the open bloom with a pad-shaped
/// shadow under it, so it reads as floating rather than pinned to the water.
struct SceneryWaterLily: View {
    var diameter: CGFloat
    var petalColor: Color
    var innerColor: Color
    var coreColor: Color

    var body: some View {
        ZStack {
            Ellipse()
                .fill(Color.black.opacity(0.12))
                .frame(width: diameter * 1.0, height: diameter * 0.22)
                .offset(y: diameter * 0.18)

            bloom
                // Flattened by the same amount as the pads around it: a lily
                // seen from the bank is lying on the water, not facing the sky.
                .scaleEffect(x: 1, y: 0.56)
        }
        .frame(width: diameter * 1.1, height: diameter * 0.70)
    }

    private var bloom: some View {
        ZStack {
            SceneryBloom(diameter: diameter, petals: 8,
                         petalColor: petalColor, coreColor: petalColor,
                         petalRatio: 0.30)
            SceneryBloom(diameter: diameter * 0.62, petals: 6,
                         petalColor: innerColor, coreColor: coreColor,
                         petalRatio: 0.34)
                .rotationEffect(.degrees(24))
        }
    }
}

// MARK: - Trees

struct SceneryConifer: View {
    var width: CGFloat
    var height: CGFloat
    var foliage: Color
    var shade: Color
    var trunk: Color

    var body: some View {
        ZStack(alignment: .bottom) {
            Capsule()
                .fill(trunk)
                .frame(width: width * 0.13, height: height * 0.26)

            ForEach(0..<3, id: \.self) { index in
                let tier = CGFloat(index)
                SceneryTriangleShape()
                    .fill(index == 1 ? shade : foliage)
                    .frame(width: width * (1 - tier * 0.22),
                           height: height * 0.52)
                    .offset(y: -height * (0.18 + tier * 0.24))
            }
        }
        .frame(width: width, height: height, alignment: .bottom)
    }
}

/// A broadleaf tree. The crown is a mass of lobes painted in one colour, so no
/// seam shows between them and it reads as foliage rather than as a stack of
/// circles; a single soft highlight puts the light on one side of it.
struct SceneryCanopyTree: View {
    var width: CGFloat
    var height: CGFloat
    var crown: Color
    var crownLight: Color
    var trunk: Color

    var body: some View {
        ZStack(alignment: .bottom) {
            Path { path in
                path.move(to: CGPoint(x: width * 0.5, y: height))
                path.addLine(to: CGPoint(x: width * 0.5, y: height * 0.46))
                path.move(to: CGPoint(x: width * 0.5, y: height * 0.60))
                path.addLine(to: CGPoint(x: width * 0.33, y: height * 0.46))
                path.move(to: CGPoint(x: width * 0.5, y: height * 0.64))
                path.addLine(to: CGPoint(x: width * 0.67, y: height * 0.50))
            }
            .stroke(trunk, style: StrokeStyle(lineWidth: max(2, width * 0.055),
                                              lineCap: .round))
            .frame(width: width, height: height)

            crownMass(width, height * 0.66)
                .offset(y: -height * 0.34)
        }
        .frame(width: width, height: height, alignment: .bottom)
    }

    private func crownMass(_ w: CGFloat, _ h: CGFloat) -> some View {
        ZStack {
            Group {
                Ellipse().frame(width: w * 0.68, height: h * 0.80)
                    .offset(x: -w * 0.16, y: h * 0.07)
                Ellipse().frame(width: w * 0.64, height: h * 0.74)
                    .offset(x: w * 0.18, y: h * 0.06)
                Ellipse().frame(width: w * 0.58, height: h * 0.72)
                    .offset(y: -h * 0.13)
                Ellipse().frame(width: w * 0.92, height: h * 0.54)
                    .offset(y: h * 0.17)
            }
            .foregroundStyle(crown)

            Ellipse()
                .fill(crownLight.opacity(0.85))
                .frame(width: w * 0.38, height: h * 0.36)
                .offset(x: -w * 0.14, y: -h * 0.15)
                .blur(radius: max(2, w * 0.06))
        }
        .frame(width: w, height: h)
    }
}

/// The flat-topped tree of a dry plain: a leaning trunk under a wide, thin
/// umbrella of leaves.
struct SceneryAcacia: View {
    var width: CGFloat
    var height: CGFloat
    var crown: Color
    var crownLight: Color
    var trunk: Color

    var body: some View {
        ZStack(alignment: .bottom) {
            Path { path in
                path.move(to: CGPoint(x: width * 0.48, y: height))
                path.addQuadCurve(to: CGPoint(x: width * 0.50, y: height * 0.50),
                                  control: CGPoint(x: width * 0.39, y: height * 0.76))
                path.move(to: CGPoint(x: width * 0.49, y: height * 0.58))
                path.addQuadCurve(to: CGPoint(x: width * 0.20, y: height * 0.38),
                                  control: CGPoint(x: width * 0.31, y: height * 0.44))
                path.move(to: CGPoint(x: width * 0.50, y: height * 0.60))
                path.addQuadCurve(to: CGPoint(x: width * 0.82, y: height * 0.40),
                                  control: CGPoint(x: width * 0.70, y: height * 0.48))
            }
            .stroke(trunk, style: StrokeStyle(lineWidth: max(2, width * 0.042),
                                              lineCap: .round))
            .frame(width: width, height: height)

            ZStack {
                Ellipse().fill(crown)
                    .frame(width: width, height: height * 0.24)
                    .offset(y: height * 0.05)
                Ellipse().fill(crown)
                    .frame(width: width * 0.66, height: height * 0.26)
                    .offset(x: -width * 0.12, y: -height * 0.02)
                Ellipse().fill(crownLight.opacity(0.9))
                    .frame(width: width * 0.54, height: height * 0.15)
                    .offset(x: -width * 0.08, y: -height * 0.06)
                    .blur(radius: max(1.5, width * 0.02))
            }
            .frame(width: width, height: height * 0.34)
            .offset(y: -height * 0.52)
        }
        .frame(width: width, height: height, alignment: .bottom)
    }
}

/// A palm. Every frond springs from the same point — the top of the trunk — and
/// droops away from it, which is the difference between a palm crown and a
/// pinwheel.
struct SceneryPalm: View {
    var width: CGFloat
    var height: CGFloat
    var frond: Color
    var frondLight: Color
    var trunk: Color

    /// Where each frond points, in degrees clockwise from pointing right.
    private let angles: [Double] = [-172, -134, -96, -58, -18, 26, 166]

    var body: some View {
        // The trunk's tip, measured from the foot of the frame.
        let tipX = width * 0.50
        let tipUp = height * 0.66

        ZStack(alignment: .bottom) {
            Path { path in
                path.move(to: CGPoint(x: width * 0.28, y: height))
                path.addQuadCurve(to: CGPoint(x: tipX, y: height - tipUp),
                                  control: CGPoint(x: width * 0.27, y: height * 0.58))
            }
            .stroke(trunk, style: StrokeStyle(lineWidth: max(3, width * 0.062),
                                              lineCap: .round))
            .frame(width: width, height: height)

            crownView
                .frame(width: width, height: width)
                .offset(x: tipX - width * 0.5, y: -(tipUp - width * 0.5))
        }
        .frame(width: width, height: height, alignment: .bottom)
    }

    private var crownView: some View {
        let length = width * 0.46
        return ZStack {
            ForEach(Array(angles.enumerated()), id: \.offset) { index, angle in
                SceneryFrondShape()
                    .fill(index.isMultiple(of: 2) ? frond : frondLight)
                    .frame(width: length, height: length * 0.42)
                    .offset(x: length * 0.5)
                    .rotationEffect(.degrees(angle))
            }
            Circle()
                .fill(trunk)
                .frame(width: width * 0.07, height: width * 0.07)
        }
    }
}

/// A shrub: a few overlapping domes, the cheapest way to fill a horizon or an
/// edge with something living.
struct SceneryBush: View {
    var width: CGFloat
    var height: CGFloat
    var color: Color
    var light: Color

    var body: some View {
        ZStack(alignment: .bottom) {
            Ellipse().fill(color)
                .frame(width: width * 0.62, height: height * 0.82)
                .offset(x: -width * 0.18)
            Ellipse().fill(light)
                .frame(width: width * 0.58, height: height)
                .offset(x: width * 0.16)
            Ellipse().fill(color)
                .frame(width: width * 0.5, height: height * 0.72)
        }
        .frame(width: width, height: height, alignment: .bottom)
    }
}

// MARK: - Built things

/// A picket fence, for a garden and for an enclosure.
struct SceneryFence: View {
    var width: CGFloat
    var height: CGFloat
    var pickets: Int
    var color: Color
    var shade: Color

    var body: some View {
        ZStack {
            ForEach(0..<pickets, id: \.self) { index in
                let step = width / CGFloat(pickets)
                RoundedRectangle(cornerRadius: height * 0.06)
                    .fill(color)
                    .frame(width: step * 0.42, height: height)
                    .offset(x: step * (CGFloat(index) + 0.5) - width * 0.5)
            }
            Rectangle().fill(shade)
                .frame(width: width, height: height * 0.10)
                .offset(y: -height * 0.22)
            Rectangle().fill(shade)
                .frame(width: width, height: height * 0.10)
                .offset(y: height * 0.20)
        }
        .frame(width: width, height: height)
    }
}

/// A signboard on two posts. Deliberately wordless: it carries two painted
/// bands in the character's own colours instead of text that would need
/// translating in ten languages.
struct SceneryZooSign: View {
    var width: CGFloat
    var height: CGFloat
    var board: Color
    var post: Color
    var accent: Color
    var accentDeep: Color

    var body: some View {
        ZStack(alignment: .bottom) {
            HStack(spacing: width * 0.5) {
                Capsule().fill(post).frame(width: width * 0.07, height: height)
                Capsule().fill(post).frame(width: width * 0.07, height: height)
            }
            RoundedRectangle(cornerRadius: height * 0.10)
                .fill(board)
                .frame(width: width, height: height * 0.52)
                .overlay {
                    VStack(spacing: height * 0.045) {
                        Capsule().fill(accentDeep)
                            .frame(width: width * 0.62, height: height * 0.075)
                        Capsule().fill(accent)
                            .frame(width: width * 0.44, height: height * 0.065)
                    }
                }
                .offset(y: -height * 0.44)
        }
        .frame(width: width, height: height, alignment: .bottom)
    }
}

struct SceneryHayBale: View {
    var width: CGFloat
    var height: CGFloat
    var straw: Color
    var strawLight: Color

    var body: some View {
        RoundedRectangle(cornerRadius: height * 0.24)
            .fill(LinearGradient(colors: [strawLight, straw],
                                 startPoint: .top, endPoint: .bottom))
            .overlay {
                // Straw ends, and the two cords holding the bale together.
                ZStack {
                    ForEach(0..<9, id: \.self) { index in
                        Capsule()
                            .fill(straw.opacity(0.5))
                            .frame(width: max(1, width * 0.016), height: height * 0.5)
                            .rotationEffect(.degrees(Double(index % 3) * 9 - 9))
                            .offset(x: width * (CGFloat(index) * 0.1 - 0.4),
                                    y: height * (CGFloat(index % 3) * 0.12 - 0.1))
                    }
                    VStack(spacing: height * 0.34) {
                        Capsule().fill(straw.opacity(0.9))
                            .frame(width: width * 0.86, height: max(1.5, height * 0.055))
                        Capsule().fill(straw.opacity(0.9))
                            .frame(width: width * 0.86, height: max(1.5, height * 0.055))
                    }
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: height * 0.24)
                    .stroke(straw.opacity(0.9), lineWidth: max(1, height * 0.04))
            }
            .frame(width: width, height: height)
    }
}

// MARK: - Underwater

struct SceneryKelp: View {
    var width: CGFloat
    var height: CGFloat
    var color: Color
    var light: Color

    var body: some View {
        ZStack(alignment: .bottom) {
            Path { path in
                path.move(to: CGPoint(x: width * 0.5, y: height))
                path.addCurve(to: CGPoint(x: width * 0.5, y: 0),
                              control1: CGPoint(x: width * 1.1, y: height * 0.62),
                              control2: CGPoint(x: 0, y: height * 0.34))
            }
            .stroke(color, style: StrokeStyle(lineWidth: max(2, width * 0.14),
                                              lineCap: .round))
            .frame(width: width, height: height)

            ForEach(0..<8, id: \.self) { index in
                let level = CGFloat(index) / 8
                SceneryLeafShape()
                    .fill(index.isMultiple(of: 2) ? light : color)
                    .frame(width: width * (1.5 - level * 0.55), height: width * 0.42)
                    .rotationEffect(.degrees(index.isMultiple(of: 2) ? -22 : 18))
                    .offset(x: index.isMultiple(of: 2)
                            ? width * (0.72 - level * 0.24) : -width * (0.72 - level * 0.24),
                            y: -height * (0.13 + level * 0.79))
            }
        }
        .frame(width: width, height: height, alignment: .bottom)
    }
}

struct SceneryCoral: View {
    var width: CGFloat
    var height: CGFloat
    var color: Color
    var light: Color
    var branches: Int = 5

    var body: some View {
        ZStack(alignment: .bottom) {
            ForEach(0..<branches, id: \.self) { index in
                let step = Double((index + 1) / 2) / Double(max(1, branches / 2))
                let spread = index.isMultiple(of: 2) ? -step : step
                let arm = height * (1 - CGFloat(abs(spread)) * 0.34)
                // Each arm is a stalk with a bud on the end, so a colony reads
                // as coral rather than as a bundle of sticks.
                ZStack(alignment: .bottom) {
                    Capsule()
                        .fill(index.isMultiple(of: 3) ? light : color)
                        .frame(width: width * 0.20, height: arm)
                    Circle()
                        .fill(index.isMultiple(of: 3) ? light : color)
                        .frame(width: width * 0.29, height: width * 0.29)
                        .offset(y: -arm + width * 0.15)
                    Circle()
                        .fill(Color.white.opacity(0.20))
                        .frame(width: width * 0.11, height: width * 0.11)
                        .offset(x: -width * 0.05, y: -arm + width * 0.13)
                }
                .frame(width: width * 0.3, height: arm, alignment: .bottom)
                .rotationEffect(.degrees(spread * 32), anchor: .bottom)
            }
            Ellipse()
                .fill(color)
                .frame(width: width * 0.74, height: height * 0.17)
        }
        .frame(width: width, height: height, alignment: .bottom)
    }
}

struct SceneryAnemone: View {
    var width: CGFloat
    var height: CGFloat
    var color: Color
    var tip: Color

    var body: some View {
        ZStack(alignment: .bottom) {
            ForEach(0..<9, id: \.self) { index in
                let spread = Double(index) / 8 * 2 - 1
                Capsule()
                    .fill(LinearGradient(colors: [tip, color],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: width * 0.12,
                           height: height * (1 - CGFloat(abs(spread)) * 0.30))
                    .rotationEffect(.degrees(spread * 58), anchor: .bottom)
            }
            Ellipse()
                .fill(color)
                .frame(width: width * 0.52, height: height * 0.2)
        }
        .frame(width: width, height: height, alignment: .bottom)
    }
}

struct SceneryStarfish: View {
    var width: CGFloat
    var color: Color
    var light: Color

    var body: some View {
        SceneryStarShape(points: 5, innerRatio: 0.46)
            .fill(LinearGradient(colors: [light, color],
                                 startPoint: .top, endPoint: .bottom))
            .overlay {
                SceneryStarShape(points: 5, innerRatio: 0.46)
                    .stroke(color.opacity(0.6), lineWidth: 1)
            }
            .frame(width: width, height: width)
    }
}

struct SceneryShell: View {
    var width: CGFloat
    var color: Color
    var line: Color

    var body: some View {
        SceneryPieShape(spread: 150)
            .fill(LinearGradient(colors: [color, line],
                                 startPoint: .top, endPoint: .bottom))
            .overlay {
                ForEach(0..<4, id: \.self) { index in
                    Capsule()
                        .fill(line.opacity(0.55))
                        .frame(width: max(1, width * 0.02), height: width * 0.42)
                        .offset(y: -width * 0.09)
                        .rotationEffect(.degrees(Double(index) * 22 - 33), anchor: .bottom)
                }
            }
            .frame(width: width, height: width * 0.52)
    }
}

struct SceneryIceberg: View {
    var width: CGFloat
    var height: CGFloat
    var ice: Color
    var shade: Color

    var body: some View {
        ZStack {
            Path { path in
                path.move(to: CGPoint(x: 0, y: height))
                path.addLine(to: CGPoint(x: width * 0.22, y: height * 0.22))
                path.addLine(to: CGPoint(x: width * 0.44, y: height * 0.55))
                path.addLine(to: CGPoint(x: width * 0.66, y: 0))
                path.addLine(to: CGPoint(x: width, y: height))
                path.closeSubpath()
            }
            .fill(LinearGradient(colors: [ice, shade],
                                 startPoint: .top, endPoint: .bottom))
        }
        .frame(width: width, height: height)
    }
}

struct SceneryMushroom: View {
    var width: CGFloat
    var cap: Color
    var stem: Color

    var body: some View {
        ZStack(alignment: .bottom) {
            Capsule()
                .fill(stem)
                .frame(width: width * 0.28, height: width * 0.62)
            SceneryPieShape(spread: 176)
                .fill(cap)
                .frame(width: width, height: width * 0.46)
                .overlay(alignment: .top) {
                    Circle().fill(Color.white.opacity(0.6))
                        .frame(width: width * 0.14, height: width * 0.14)
                        .offset(x: -width * 0.1, y: width * 0.1)
                }
                .offset(y: -width * 0.5)
        }
        .frame(width: width, height: width * 0.96, alignment: .bottom)
    }
}
