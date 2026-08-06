//
//  CharacterScenes.swift
//  Hungry Frog
//
//  One habitat per character: the frog plays over its pond, the penguin over
//  polar water, the octopus on the seabed, the bear in a pine forest. Each
//  scene is drawn from the shared pieces in Scenery.swift and painted partly in
//  the character's own theme colours, so the backdrop belongs to the animal
//  reclining on it rather than being one pond with ten different tints.
//
//  Every scene owes the game two things. It has to put a piece of solid ground
//  under the lounger — the pose is a beach lounger, and a lounger stands on
//  land — and it has to stay quiet enough that a swarm of numbered food is
//  readable over it. Contrast is kept low and busy detail is kept to the edges
//  and the foot of the scene, out of the airspace the flies work.
//
//  A scene is drawn in two layers. Everything still is flattened into a single
//  texture that is produced once and composited untouched from then on; the
//  handful of pieces that move sit in a thin layer above it, each carrying one
//  render-server animation. The character itself never moves.
//

import SwiftUI

// MARK: - Geometry

/// The measurements every scene is laid out against: the screen, the frame the
/// reclining pose is drawn in, and the height the scene's ground line sits at.
struct SceneGeometry {
    let size: CGSize
    /// Where the character's artwork is drawn, so the ground can be put under
    /// its lounger instead of somewhere near it.
    let stage: CGRect
    /// The scene's ground line: a waterline, a shore, a seabed, a forest floor.
    let horizon: CGFloat
    let unit: CGFloat

    init(size: CGSize, stage: CGRect, horizon: CGFloat) {
        self.size = size
        self.stage = stage
        self.horizon = horizon
        self.unit = Scenery.unit(for: size)
    }

    func x(_ share: CGFloat) -> CGFloat { size.width * share }
    func y(_ share: CGFloat) -> CGFloat { size.height * share }
    /// Scenery units, the measure decor is sized in.
    func u(_ count: CGFloat) -> CGFloat { count * unit }
    /// A height given in scenery units below the ground line.
    func under(_ count: CGFloat) -> CGFloat { horizon + count * unit }

    /// Everything from the ground line to the bottom edge.
    var floorHeight: CGFloat { max(1, size.height - horizon) }
    var floorCenter: CGFloat { horizon + floorHeight * 0.5 }

    /// The bank the lounger stands on. Its crown has to run *behind* the far
    /// legs rather than level with them: all ten poses put the head-end foot at
    /// about 0.79 of the artwork's height, so a crown at that line leaves the
    /// back of the lounger standing on the very lip of its own ground. Held
    /// well above it, there is bank behind the far feet and bank in front of
    /// the near ones.
    var groundTop: CGFloat { stage.minY + stage.height * 0.66 }
    var groundWidth: CGFloat { min(size.width * 0.82, stage.width * 2.6) }
    var groundDepth: CGFloat { max(size.height * 0.17, size.height - groundTop + u(6)) }
    var groundCenter: CGPoint { CGPoint(x: stage.midX, y: groundTop + groundDepth * 0.5) }
    /// A spot on the bank beside the lounger: `side` is -1 for the left
    /// shoulder and 1 for the right, and `step` walks further out. Both stay on
    /// the level part of the crown, so nothing is left standing in mid-air over
    /// the edge of its own ground.
    func beside(_ side: CGFloat, step: CGFloat) -> CGPoint {
        CGPoint(x: stage.midX + side * groundWidth * (0.19 + step * 0.033),
                y: groundTop + u(14 + step * 3.5))
    }
}

/// Birds crossing the sky. Each one gets its own height, wingspan, pace and
/// moment of setting off, which is what stops a flock reading as one object
/// sliding sideways. They always start and finish out of frame, so the loop
/// never restarts on screen.
///
/// This belongs in a scene's moving layer, never in its still one: birds in a
/// flattened backdrop are birds nailed to the sky.
private struct SkyFlight: View {
    let geo: SceneGeometry
    var count: Int = 3
    /// Wingspan of the nearest bird, in scenery units.
    var span: CGFloat = 20
    /// Where the highest bird flies, as a share of the scene's height.
    var topShare: CGFloat = 0.18
    var color: Color
    var period: Double = 27
    var rightwards: Bool = true

    var body: some View {
        ForEach(0..<count, id: \.self) { index in
            let width = geo.u(span - CGFloat(index) * span * 0.16)
            SceneryBird(width: width, color: color)
                .position(x: rightwards ? -geo.u(36) : geo.size.width + geo.u(36),
                          y: geo.y(topShare + CGFloat(index) * 0.052))
                .sceneryDrift(dx: (rightwards ? 1 : -1) * (geo.size.width + geo.u(100)),
                              dy: geo.u(CGFloat(index % 3) * 11 - 11),
                              period: period + Double(index) * 6,
                              delay: Double(index) * 5.5)
        }
    }
}

/// A thin band of high haze crossing the sky far more slowly than any cloud.
/// Cheap way to keep an empty top third of a scene from sitting perfectly
/// still without adding anything the eye has to look at.
private struct SkyWisp: View {
    let geo: SceneGeometry
    var heightShare: CGFloat
    var lengthShare: CGFloat = 0.42
    var color: Color = .white
    var opacity: Double = 0.30
    var period: Double = 150
    var delay: Double = 0

    var body: some View {
        Capsule()
            .fill(color.opacity(opacity))
            .frame(width: geo.x(lengthShare), height: geo.u(16))
            .blur(radius: geo.u(9))
            .position(x: -geo.x(lengthShare * 0.6), y: geo.y(heightShare))
            .sceneryDrift(dx: geo.size.width + geo.x(lengthShare * 1.2),
                          period: period, delay: delay)
    }
}

/// The shadow the lounger casts on whatever it is standing on. Without it the
/// pose floats a little above its own ground however well the bank is drawn.
private struct LoungerShadow: View {
    let geo: SceneGeometry
    var opacity: Double = 0.17

    var body: some View {
        Ellipse()
            .fill(Color.black.opacity(opacity))
            .frame(width: geo.stage.width * 0.92, height: geo.u(20))
            .blur(radius: geo.u(7))
            .position(x: geo.stage.midX, y: geo.stage.maxY - geo.stage.height * 0.045)
    }
}

/// Places decor with its foot at a point, which is how a plant, a tree or a
/// rock is naturally positioned.
private struct Planted<Content: View>: View {
    let x: CGFloat
    let footY: CGFloat
    let width: CGFloat
    let height: CGFloat
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .frame(width: width, height: height, alignment: .bottom)
            .position(x: x, y: footY - height * 0.5)
    }
}

// MARK: - Dispatcher

/// The backdrop a level is played against, chosen by character.
struct CharacterBackdrop: View {
    let character: AnimalCharacter
    let stage: CGRect
    let horizon: CGFloat
    let reduceMotion: Bool

    var body: some View {
        GeometryReader { proxy in
            let geo = SceneGeometry(size: proxy.size, stage: stage, horizon: horizon)
            scene(geo)
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func scene(_ geo: SceneGeometry) -> some View {
        let motion = !reduceMotion
        switch character.id {
        case "penguin":
            PolarScene(character: character, geo: geo, showsMotion: motion)
        case "bunny":
            MeadowScene(character: character, geo: geo, showsMotion: motion)
        case "dog":
            GardenScene(character: character, geo: geo, showsMotion: motion)
        case "lion":
            SavannahScene(character: character, geo: geo, showsMotion: motion)
        case "octopus":
            ReefScene(character: character, geo: geo, showsMotion: motion)
        case "crab":
            BeachScene(character: character, geo: geo, showsMotion: motion)
        case "elephant":
            ZooScene(character: character, geo: geo, showsMotion: motion)
        case "bear":
            ForestScene(character: character, geo: geo, showsMotion: motion)
        case "fox":
            AutumnScene(character: character, geo: geo, showsMotion: motion)
        default:
            PondScene(character: character, geo: geo, showsMotion: motion)
        }
    }
}

// MARK: - Frog: the pond

private struct PondScene: View {
    let character: AnimalCharacter
    let geo: SceneGeometry
    let showsMotion: Bool

    private let skyTop = Color(red: 0.62, green: 0.87, blue: 0.98)
    private let skyLow = Color(red: 0.86, green: 0.95, blue: 0.83)
    private let farBank = Color(red: 0.25, green: 0.58, blue: 0.25)
    private let bankShade = Color(red: 0.17, green: 0.44, blue: 0.18)
    private let waterTop = Color(red: 0.27, green: 0.72, blue: 0.78)
    private let waterDeep = Color(red: 0.08, green: 0.47, blue: 0.64)
    private let reedGreen = Color(red: 0.17, green: 0.48, blue: 0.16)
    private let reedLight = Color(red: 0.30, green: 0.62, blue: 0.24)
    private let club = Color(red: 0.42, green: 0.24, blue: 0.10)
    private let petal = Color(red: 0.99, green: 0.94, blue: 0.98)
    private let petalInner = Color(red: 0.98, green: 0.82, blue: 0.88)
    private let pollen = Color(red: 0.99, green: 0.82, blue: 0.32)

    var body: some View {
        ZStack {
            still.drawingGroup()
            if showsMotion { motion }
        }
    }

    private var still: some View {
        ZStack {
            sky
            water
            shore
            plants
        }
    }

    private var sky: some View {
        ZStack {
            LinearGradient(colors: [skyTop, skyLow], startPoint: .top, endPoint: .bottom)

            ScenerySun(diameter: geo.u(78),
                       core: Color(red: 1.0, green: 0.91, blue: 0.48).opacity(0.82),
                       halo: Color(red: 1.0, green: 0.95, blue: 0.66))
                .position(x: geo.x(0.17), y: geo.y(0.16))

            // Far hills, hazed with the character's own green so the horizon
            // reads as the same world as the bank in front of it.
            Ellipse()
                .fill(character.tintColor.opacity(0.55))
                .frame(width: geo.x(0.86), height: geo.u(96))
                .position(x: geo.x(0.22), y: geo.horizon - geo.u(14))
            Ellipse()
                .fill(character.color.opacity(0.24))
                .frame(width: geo.x(0.72), height: geo.u(76))
                .position(x: geo.x(0.82), y: geo.horizon - geo.u(8))

        }
    }

    private var water: some View {
        ZStack {
            Ellipse()
                .fill(farBank)
                .frame(width: geo.size.width * 1.35, height: geo.u(122))
                .position(x: geo.x(0.5), y: geo.under(24))

            ForEach(0..<6, id: \.self) { index in
                let width = geo.u(64 + CGFloat(index % 3) * 26)
                let height = geo.u(28 + CGFloat(index % 4) * 9)
                Planted(x: geo.x(0.07 + CGFloat(index) * 0.18),
                        footY: geo.under(6), width: width, height: height) {
                    SceneryBush(width: width, height: height,
                                color: bankShade, light: farBank)
                }
            }

            // A stand of trees over on the far bank, small enough to read as
            // distance rather than as decoration in its own right.
            ForEach(0..<3, id: \.self) { index in
                let width = geo.u(56 + CGFloat(index % 2) * 16)
                let height = geo.u(72 + CGFloat(index % 3) * 18)
                Planted(x: geo.x(0.30 + CGFloat(index) * 0.26),
                        footY: geo.under(2), width: width, height: height) {
                    SceneryCanopyTree(width: width, height: height,
                                      crown: bankShade, crownLight: farBank,
                                      trunk: Color(red: 0.35, green: 0.26, blue: 0.15))
                        .opacity(0.92)
                }
            }

            Rectangle()
                .fill(LinearGradient(colors: [waterTop, waterDeep],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: geo.size.width, height: geo.floorHeight)
                .position(x: geo.x(0.5), y: geo.floorCenter)

            Ellipse()
                .fill(Color(red: 0.47, green: 0.86, blue: 0.88).opacity(0.72))
                .frame(width: geo.size.width * 1.16, height: geo.u(48))
                .position(x: geo.x(0.5), y: geo.horizon)

            ForEach(0..<5, id: \.self) { index in
                Capsule()
                    .fill(Color.white.opacity(0.20))
                    .frame(width: geo.u(64), height: geo.u(5))
                    .position(x: geo.x(0.12 + CGFloat(index) * 0.19),
                              y: geo.under(CGFloat(index % 2) * 36 + 8))
            }
        }
    }

    private var shore: some View {
        ZStack {
            SceneryGroundPatch(width: geo.groundWidth, height: geo.groundDepth,
                               crownColor: Color(red: 0.51, green: 0.73, blue: 0.33),
                               earthColor: Color(red: 0.34, green: 0.26, blue: 0.14),
                               rimColor: Color(red: 0.92, green: 0.87, blue: 0.64))
                .position(geo.groundCenter)

            // Grass along the crown, on both shoulders of the bank, so the
            // lounger reads as standing on a bank rather than on a shape.
            ForEach(0..<5, id: \.self) { index in
                let spot = geo.beside(index.isMultiple(of: 2) ? -1 : 1,
                                      step: CGFloat(index / 2))
                Planted(x: spot.x, footY: spot.y,
                        width: geo.u(34), height: geo.u(24 + CGFloat(index % 3) * 6)) {
                    SceneryTuft(width: geo.u(34), height: geo.u(24 + CGFloat(index % 3) * 6),
                                color: reedGreen, light: reedLight, blades: 6)
                }
            }

            ForEach(0..<5, id: \.self) { index in
                let width = geo.u(15 + CGFloat(index % 3) * 7)
                let height = geo.u(8 + CGFloat(index % 3) * 3)
                Planted(x: geo.beside(index.isMultiple(of: 2) ? -1 : 1,
                                              step: 2.1 + CGFloat(index / 2) * 0.8).x,
                        footY: geo.beside(index.isMultiple(of: 2) ? -1 : 1,
                                          step: 2.1 + CGFloat(index / 2) * 0.8).y,
                        width: width, height: height) {
                    SceneryRock(width: width, height: height,
                                color: Color(red: 0.58, green: 0.55, blue: 0.50),
                                light: Color(red: 0.78, green: 0.75, blue: 0.70))
                }
            }

            LoungerShadow(geo: geo)
        }
    }

    private var plants: some View {
        ZStack {
            // The left-hand stand of marsh plants. Each cattail and the flower
            // are single plants, so nothing sits beside its own stem.
            Planted(x: geo.x(0.055), footY: geo.under(20),
                    width: geo.u(40), height: geo.u(112)) {
                SceneryTuft(width: geo.u(40), height: geo.u(112),
                            color: reedGreen, light: reedLight, blades: 7)
            }

            Planted(x: geo.x(0.10), footY: geo.under(12),
                    width: geo.u(34), height: geo.u(78)) {
                SceneryTuft(width: geo.u(34), height: geo.u(78),
                            color: bankShade, light: reedGreen, blades: 5)
            }

            ForEach(0..<3, id: \.self) { index in
                Planted(x: geo.x(0.032 + CGFloat(index) * 0.026),
                        footY: geo.under(14 + CGFloat(index) * 5),
                        width: geo.u(18), height: geo.u(96 + CGFloat(index) * 14)) {
                    SceneryCattail(height: geo.u(96 + CGFloat(index) * 14),
                                   stemColor: reedGreen, clubColor: club,
                                   lean: Double(index) * 4 - 5)
                }
            }

            Planted(x: geo.x(0.135), footY: geo.under(16),
                    width: geo.u(60), height: geo.u(86)) {
                SceneryFlowerPlant(height: geo.u(86), stemColor: reedLight,
                                   leafColor: reedGreen, petalColor: pollen,
                                   coreColor: club, petals: 6, lean: 4)
            }

            // The right bank: a smaller stand, so the scene is not lopsided.
            Planted(x: geo.x(0.955), footY: geo.under(16),
                    width: geo.u(36), height: geo.u(88)) {
                SceneryTuft(width: geo.u(36), height: geo.u(88),
                            color: reedGreen, light: reedLight, blades: 6)
            }

            Planted(x: geo.x(0.90), footY: geo.under(10),
                    width: geo.u(46), height: geo.u(66)) {
                SceneryFlowerPlant(height: geo.u(66), stemColor: reedLight,
                                   leafColor: reedGreen,
                                   petalColor: petalInner, coreColor: pollen,
                                   petals: 5, lean: -6)
            }
        }
    }

    private var motion: some View {
        ZStack {
            SceneryCloud(width: geo.u(104))
                .position(x: -geo.u(80), y: geo.y(0.15))
                .sceneryDrift(dx: geo.size.width + geo.u(230), period: 96)

            SceneryCloud(width: geo.u(76), opacity: 0.62)
                .position(x: -geo.u(60), y: geo.y(0.30))
                .sceneryDrift(dx: geo.size.width + geo.u(190), period: 138, delay: 12)

            SkyWisp(geo: geo, heightShare: 0.09, color: .white, opacity: 0.34,
                    period: 176)

            SkyFlight(geo: geo, count: 3, span: 17, topShare: 0.17,
                      color: bankShade.opacity(0.34), period: 30)

            SkyFlight(geo: geo, count: 2, span: 12, topShare: 0.30,
                      color: bankShade.opacity(0.24), period: 44,
                      rightwards: false)

            // Pads and lilies ride the surface.
            Group {
                SceneryLilyPad(width: geo.u(98), height: geo.u(44),
                               color: character.color, deepColor: bankShade,
                               notchAngle: -8)
                    .position(x: geo.x(0.17), y: geo.under(38))
                    .sceneryBob(dx: geo.u(2), dy: geo.u(3), period: 4.6)

                SceneryLilyPad(width: geo.u(62), height: geo.u(28),
                               color: character.color.opacity(0.9), deepColor: bankShade,
                               notchAngle: 140)
                    .position(x: geo.x(0.31), y: geo.under(20))
                    .sceneryBob(dx: geo.u(2), dy: geo.u(2), period: 5.4, delay: 0.8)

                SceneryLilyPad(width: geo.u(80), height: geo.u(36),
                               color: character.color, deepColor: bankShade,
                               notchAngle: 168)
                    .position(x: geo.x(0.855), y: geo.under(24))
                    .sceneryBob(dx: geo.u(2), dy: geo.u(3), period: 5.0, delay: 1.6)

                SceneryWaterLily(diameter: geo.u(34), petalColor: petal,
                                 innerColor: petalInner, coreColor: pollen)
                    .position(x: geo.x(0.245), y: geo.under(28))
                    .sceneryBob(dy: geo.u(2.5), period: 5.2, delay: 0.4)

                SceneryWaterLily(diameter: geo.u(26), petalColor: petal,
                                 innerColor: petalInner, coreColor: pollen)
                    .position(x: geo.x(0.905), y: geo.under(14))
                    .sceneryBob(dy: geo.u(2), period: 6.0, delay: 2.1)

                SceneryLilyPad(width: geo.u(52), height: geo.u(23),
                               color: character.color.opacity(0.85), deepColor: bankShade,
                               notchAngle: 42)
                    .position(x: geo.x(0.63), y: geo.under(12))
                    .sceneryBob(dx: geo.u(2), dy: geo.u(2), period: 6.2, delay: 2.6)

                SceneryLilyPad(width: geo.u(44), height: geo.u(19),
                               color: character.color.opacity(0.8), deepColor: bankShade,
                               notchAngle: 205)
                    .position(x: geo.x(0.06), y: geo.under(22))
                    .sceneryBob(dx: geo.u(2), dy: geo.u(2), period: 5.8, delay: 3.2)
            }

            SceneryDragonfly(width: geo.u(26), bodyColor: bankShade,
                             wing: Color.white)
                .position(x: -geo.u(40), y: geo.under(-30))
                .sceneryDrift(dx: geo.size.width + geo.u(90), dy: geo.u(26), period: 21)

            // Rings spreading where something small has broken the surface.
            ForEach(0..<3, id: \.self) { index in
                Ellipse()
                    .strokeBorder(Color.white.opacity(0.42),
                                  lineWidth: max(1, geo.u(2)))
                    .frame(width: geo.u(46), height: geo.u(16))
                    .sceneryRipple(period: 3.6 + Double(index) * 0.7,
                                   delay: Double(index) * 1.5)
                    .position(x: geo.x(0.40 + CGFloat(index) * 0.14),
                              y: geo.under(16 + CGFloat(index % 2) * 26))
            }

            // Leaves that have come off the far bank and are drifting across.
            ForEach(0..<2, id: \.self) { index in
                SceneryLeafShape()
                    .fill(Color(red: 0.78, green: 0.66, blue: 0.30).opacity(0.8))
                    .frame(width: geo.u(20), height: geo.u(9))
                    .rotationEffect(.degrees(Double(index) * 40 - 20))
                    .position(x: -geo.u(30), y: geo.under(24 + CGFloat(index) * 30))
                    .sceneryDrift(dx: geo.size.width + geo.u(70), dy: geo.u(10),
                                  period: 54 + Double(index) * 16,
                                  delay: Double(index) * 9)
            }

            // The marsh stand answering the breeze the clouds are riding.
            Group {
                SceneryCattail(height: geo.u(110), stemColor: reedGreen, clubColor: club)
                    .frame(width: geo.u(18), height: geo.u(110), alignment: .bottom)
                    .scenerySway(2.6, period: 5.2)
                    .position(x: geo.x(0.115), y: geo.under(18) - geo.u(55))

                SceneryFlowerPlant(height: geo.u(70), stemColor: reedLight,
                                   leafColor: reedGreen, petalColor: pollen,
                                   coreColor: club, petals: 6)
                    .frame(width: geo.u(50), height: geo.u(70), alignment: .bottom)
                    .scenerySway(3.4, period: 4.4, delay: 0.9)
                    .position(x: geo.x(0.175), y: geo.under(12) - geo.u(35))

                SceneryTuft(width: geo.u(30), height: geo.u(64),
                            color: reedGreen, light: reedLight, blades: 5)
                    .frame(width: geo.u(30), height: geo.u(64), alignment: .bottom)
                    .scenerySway(3.0, period: 5.8, delay: 1.7)
                    .position(x: geo.x(0.925), y: geo.under(8) - geo.u(32))
            }
        }
    }
}

// MARK: - Penguin: polar water

private struct PolarScene: View {
    let character: AnimalCharacter
    let geo: SceneGeometry
    let showsMotion: Bool

    // Deep enough at the top for the aurora to have something to show against.
    private let skyTop = Color(red: 0.24, green: 0.42, blue: 0.78)
    private let skyLow = Color(red: 0.88, green: 0.95, blue: 0.99)
    private let ice = Color(red: 0.97, green: 0.99, blue: 1.0)
    private let iceShade = Color(red: 0.72, green: 0.86, blue: 0.96)
    private let waterTop = Color(red: 0.26, green: 0.55, blue: 0.82)
    private let waterDeep = Color(red: 0.05, green: 0.18, blue: 0.40)

    var body: some View {
        ZStack {
            still.drawingGroup()
            if showsMotion { motion }
        }
    }

    private var still: some View {
        ZStack {
            sky
            water
            shore
        }
    }

    private var sky: some View {
        ZStack {
            LinearGradient(colors: [skyTop, skyLow], startPoint: .top, endPoint: .bottom)

            ScenerySun(diameter: geo.u(60),
                       core: Color(red: 1.0, green: 0.97, blue: 0.88).opacity(0.9),
                       halo: Color(red: 0.94, green: 0.98, blue: 1.0))
                .position(x: geo.x(0.80), y: geo.y(0.15))

            // A ridge of ice cliffs along the far side of the water.
            ForEach(0..<5, id: \.self) { index in
                let width = geo.u(96 + CGFloat(index % 3) * 44)
                let height = geo.u(46 + CGFloat(index % 4) * 20)
                Planted(x: geo.x(0.06 + CGFloat(index) * 0.22),
                        footY: geo.horizon - geo.u(4), width: width, height: height) {
                    SceneryIceberg(width: width, height: height,
                                   ice: ice.opacity(0.94), shade: iceShade)
                }
            }

            Ellipse()
                .fill(ice.opacity(0.92))
                .frame(width: geo.size.width * 1.3, height: geo.u(66))
                .position(x: geo.x(0.5), y: geo.horizon - geo.u(2))

            // Snow drifts along the front of the shelf, catching the low sun.
            ForEach(0..<4, id: \.self) { index in
                let width = geo.u(120 + CGFloat(index % 3) * 40)
                let height = geo.u(20 + CGFloat(index % 3) * 8)
                Planted(x: geo.x(0.10 + CGFloat(index) * 0.27),
                        footY: geo.horizon + geo.u(4), width: width, height: height) {
                    SceneryRock(width: width, height: height,
                                color: iceShade.opacity(0.8), light: ice)
                }
            }
        }
    }

    private var water: some View {
        ZStack {
            Rectangle()
                .fill(LinearGradient(colors: [waterTop, waterDeep],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: geo.size.width, height: geo.floorHeight)
                .position(x: geo.x(0.5), y: geo.floorCenter)

            Ellipse()
                .fill(character.tintColor.opacity(0.55))
                .frame(width: geo.size.width * 1.14, height: geo.u(46))
                .position(x: geo.x(0.5), y: geo.horizon)

            ForEach(0..<5, id: \.self) { index in
                Capsule()
                    .fill(Color.white.opacity(0.18))
                    .frame(width: geo.u(70), height: geo.u(5))
                    .position(x: geo.x(0.10 + CGFloat(index) * 0.21),
                              y: geo.under(CGFloat(index % 2) * 34 + 12))
            }
        }
    }

    private var shore: some View {
        ZStack {
            SceneryGroundPatch(width: geo.groundWidth, height: geo.groundDepth,
                               crownColor: ice,
                               earthColor: Color(red: 0.55, green: 0.75, blue: 0.92),
                               rimColor: Color(red: 0.85, green: 0.95, blue: 1.0))
                .position(geo.groundCenter)

            // Broken ice heaped along the edge of the floe.
            ForEach(0..<6, id: \.self) { index in
                let spot = geo.beside(index.isMultiple(of: 2) ? -1 : 1,
                                      step: CGFloat(index / 2))
                Planted(x: spot.x, footY: spot.y,
                        width: geo.u(30 + CGFloat(index % 3) * 10),
                        height: geo.u(14 + CGFloat(index % 3) * 6)) {
                    SceneryRock(width: geo.u(30 + CGFloat(index % 3) * 10),
                                height: geo.u(14 + CGFloat(index % 3) * 6),
                                color: iceShade, light: ice)
                }
            }

            ForEach(0..<3, id: \.self) { index in
                SceneryStarShape(points: 6, innerRatio: 0.3)
                    .fill(Color.white.opacity(0.5))
                    .frame(width: geo.u(12), height: geo.u(12))
                    .position(geo.beside(index.isMultiple(of: 2) ? -1 : 1,
                                         step: 2.4 + CGFloat(index) * 0.5))
            }

            // Pressure ridges heaped up at both edges of the floe, so the
            // corners of the scene are not bare water.
            ForEach(0..<5, id: \.self) { index in
                let width = geo.u(72 + CGFloat(index % 3) * 30)
                let height = geo.u(40 + CGFloat(index % 3) * 22)
                Planted(x: geo.x(index < 3 ? 0.02 + CGFloat(index) * 0.055
                                           : 0.94 + CGFloat(index - 3) * 0.05),
                        footY: geo.under(20 + CGFloat(index % 3) * 12),
                        width: width, height: height) {
                    SceneryIceberg(width: width, height: height,
                                   ice: ice, shade: iceShade)
                }
            }

            LoungerShadow(geo: geo, opacity: 0.12)
        }
    }

    private var motion: some View {
        ZStack {
            SceneryAurora(width: geo.size.width * 1.05, height: geo.y(0.44),
                          colors: [Color(red: 0.36, green: 0.96, blue: 0.70).opacity(0.72),
                                   Color(red: 0.52, green: 0.80, blue: 1.0).opacity(0.62),
                                   Color(red: 0.68, green: 0.96, blue: 0.88).opacity(0.58)])
                .sceneryGlow(low: 0.6, period: 7.5)
                .position(x: geo.x(0.42), y: geo.y(0.21))

            // Floes drifting past on the open water.
            SceneryRock(width: geo.u(96), height: geo.u(20), color: iceShade, light: ice)
                .position(x: geo.x(0.20), y: geo.under(54))
                .sceneryBob(dx: geo.u(4), dy: geo.u(3), period: 5.6)

            SceneryRock(width: geo.u(64), height: geo.u(14), color: iceShade, light: ice)
                .position(x: geo.x(0.86), y: geo.under(28))
                .sceneryBob(dx: geo.u(3), dy: geo.u(2), period: 6.4, delay: 1.4)

            ForEach(0..<6, id: \.self) { index in
                SceneryFlake(diameter: geo.u(5 + CGFloat(index % 3) * 2))
                    .position(x: geo.x(0.08 + CGFloat(index) * 0.16), y: -geo.u(12))
                    .sceneryDrift(dx: geo.u(CGFloat(index % 3) * 18 - 18),
                                  dy: geo.size.height + geo.u(24),
                                  period: 15 + Double(index % 4) * 4,
                                  delay: Double(index) * 2.4)
            }

            SkyFlight(geo: geo, count: 3, span: 19, topShare: 0.26,
                      color: Color(red: 0.20, green: 0.28, blue: 0.44).opacity(0.5),
                      period: 26)

            SkyFlight(geo: geo, count: 2, span: 13, topShare: 0.13,
                      color: Color(red: 0.20, green: 0.28, blue: 0.44).opacity(0.32),
                      period: 40, rightwards: false)

            SkyWisp(geo: geo, heightShare: 0.36, lengthShare: 0.5,
                    opacity: 0.24, period: 168, delay: 20)
        }
    }
}

// MARK: - Bunny: the flower meadow

private struct MeadowScene: View {
    let character: AnimalCharacter
    let geo: SceneGeometry
    let showsMotion: Bool

    private let skyTop = Color(red: 0.99, green: 0.86, blue: 0.91)
    private let skyLow = Color(red: 0.99, green: 0.97, blue: 0.91)
    private let grass = Color(red: 0.52, green: 0.76, blue: 0.36)
    private let grassDeep = Color(red: 0.33, green: 0.58, blue: 0.24)
    private let grassLight = Color(red: 0.68, green: 0.86, blue: 0.44)
    private let stem = Color(red: 0.36, green: 0.62, blue: 0.26)
    private let daisy = Color(red: 1.0, green: 0.99, blue: 0.96)
    private let pollen = Color(red: 0.99, green: 0.80, blue: 0.30)

    var body: some View {
        ZStack {
            still.drawingGroup()
            if showsMotion { motion }
        }
    }

    private var still: some View {
        ZStack {
            sky
            field
            shore
            flowers
        }
    }

    private var sky: some View {
        ZStack {
            LinearGradient(colors: [skyTop, skyLow], startPoint: .top, endPoint: .bottom)

            ScenerySun(diameter: geo.u(72),
                       core: Color(red: 1.0, green: 0.95, blue: 0.76).opacity(0.85),
                       halo: Color(red: 1.0, green: 0.90, blue: 0.86))
                .position(x: geo.x(0.16), y: geo.y(0.15))

            Ellipse()
                .fill(character.tintColor.opacity(0.60))
                .frame(width: geo.x(0.92), height: geo.u(104))
                .position(x: geo.x(0.26), y: geo.horizon - geo.u(22))
            Ellipse()
                .fill(character.color.opacity(0.22))
                .frame(width: geo.x(0.78), height: geo.u(84))
                .position(x: geo.x(0.86), y: geo.horizon - geo.u(14))
        }
    }

    private var field: some View {
        ZStack {
            Ellipse()
                .fill(grassDeep)
                .frame(width: geo.size.width * 1.4, height: geo.u(126))
                .position(x: geo.x(0.32), y: geo.under(16))
            Ellipse()
                .fill(grass)
                .frame(width: geo.size.width * 1.2, height: geo.u(104))
                .position(x: geo.x(0.78), y: geo.under(26))

            Rectangle()
                .fill(LinearGradient(colors: [grass, grassDeep],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: geo.size.width, height: geo.floorHeight)
                .position(x: geo.x(0.5), y: geo.floorCenter)

            // A hedgerow of blossom bushes along the top of the field.
            ForEach(0..<6, id: \.self) { index in
                let width = geo.u(76 + CGFloat(index % 3) * 28)
                let height = geo.u(32 + CGFloat(index % 4) * 10)
                Planted(x: geo.x(0.05 + CGFloat(index) * 0.19),
                        footY: geo.under(4), width: width, height: height) {
                    SceneryBush(width: width, height: height,
                                color: grassDeep, light: grass)
                }
            }

            ForEach(0..<3, id: \.self) { index in
                let width = geo.u(86 + CGFloat(index % 2) * 22)
                let height = geo.u(96 + CGFloat(index % 3) * 22)
                Planted(x: geo.x(0.22 + CGFloat(index) * 0.29),
                        footY: geo.under(2), width: width, height: height) {
                    SceneryCanopyTree(width: width, height: height,
                                      crown: grassDeep,
                                      crownLight: character.tintColor,
                                      trunk: Color(red: 0.44, green: 0.32, blue: 0.20))
                }
            }

            // Blossom drifted onto the hedgerow, in the bunny's own pink.
            ForEach(0..<8, id: \.self) { index in
                SceneryBloom(diameter: geo.u(11), petals: 5,
                             petalColor: character.color.opacity(0.85),
                             coreColor: pollen)
                    .position(x: geo.x(0.06 + CGFloat(index) * 0.13),
                              y: geo.horizon - geo.u(6 + CGFloat(index % 3) * 9))
            }
        }
    }

    private var shore: some View {
        ZStack {
            SceneryGroundPatch(width: geo.groundWidth, height: geo.groundDepth,
                               crownColor: grassLight,
                               earthColor: Color(red: 0.42, green: 0.30, blue: 0.18),
                               rimColor: Color(red: 0.80, green: 0.92, blue: 0.56))
                .position(geo.groundCenter)

            ForEach(0..<6, id: \.self) { index in
                let spot = geo.beside(index.isMultiple(of: 2) ? -1 : 1,
                                      step: CGFloat(index / 2))
                Planted(x: spot.x, footY: spot.y,
                        width: geo.u(32), height: geo.u(20 + CGFloat(index % 3) * 8)) {
                    SceneryTuft(width: geo.u(32), height: geo.u(20 + CGFloat(index % 3) * 8),
                                color: grassDeep, light: grass, blades: 9)
                }
            }

            LoungerShadow(geo: geo)
        }
    }

    private var flowers: some View {
        ZStack {
            // Tulips at the left, daisies at the right: the meadow's own colour
            // is the character's, so the field reads pink at a glance.
            ForEach(0..<3, id: \.self) { index in
                Planted(x: geo.x(0.045 + CGFloat(index) * 0.035),
                        footY: geo.under(24 + CGFloat(index) * 8),
                        width: geo.u(56), height: geo.u(84 + CGFloat(index) * 12)) {
                    SceneryFlowerPlant(height: geo.u(84 + CGFloat(index) * 12),
                                       stemColor: stem, leafColor: grassDeep,
                                       petalColor: character.color,
                                       coreColor: pollen, petals: 5,
                                       lean: Double(index) * 5 - 6)
                }
            }

            Planted(x: geo.x(0.15), footY: geo.under(18),
                    width: geo.u(40), height: geo.u(66)) {
                SceneryTuft(width: geo.u(40), height: geo.u(66),
                            color: grassDeep, light: grassLight, blades: 7)
            }

            ForEach(0..<2, id: \.self) { index in
                Planted(x: geo.x(0.93 + CGFloat(index) * 0.045),
                        footY: geo.under(20 + CGFloat(index) * 10),
                        width: geo.u(52), height: geo.u(72 + CGFloat(index) * 14)) {
                    SceneryFlowerPlant(height: geo.u(72 + CGFloat(index) * 14),
                                       stemColor: stem, leafColor: grassDeep,
                                       petalColor: daisy, coreColor: pollen,
                                       petals: 8, lean: Double(index) * 6 - 3)
                }
            }

            // Low blooms scattered across the field, kept small and pale so the
            // flying numbers stay the brightest thing on screen.
            ForEach(0..<7, id: \.self) { index in
                SceneryBloom(diameter: geo.u(13 + CGFloat(index % 3) * 3),
                             petals: 5,
                             petalColor: index.isMultiple(of: 3)
                                ? daisy.opacity(0.9)
                                : character.color.opacity(0.75),
                             coreColor: pollen)
                    .position(x: geo.x(0.06 + CGFloat(index) * 0.135),
                              y: geo.under(6 + CGFloat(index % 4) * 12))
            }
        }
    }

    private var motion: some View {
        ZStack {
            SceneryCloud(width: geo.u(100))
                .position(x: -geo.u(76), y: geo.y(0.14))
                .sceneryDrift(dx: geo.size.width + geo.u(220), period: 104)

            SceneryCloud(width: geo.u(72), opacity: 0.6)
                .position(x: -geo.u(56), y: geo.y(0.28))
                .sceneryDrift(dx: geo.size.width + geo.u(180), period: 146, delay: 16)

            SkyFlight(geo: geo, count: 3, span: 17, topShare: 0.20,
                      color: grassDeep.opacity(0.40), period: 28)

            SkyFlight(geo: geo, count: 2, span: 12, topShare: 0.09,
                      color: grassDeep.opacity(0.26), period: 43, rightwards: false)

            Group {
                SceneryFlowerPlant(height: geo.u(92), stemColor: stem,
                                   leafColor: grassDeep, petalColor: character.color,
                                   coreColor: pollen, petals: 5)
                    .frame(width: geo.u(64), height: geo.u(92), alignment: .bottom)
                    .scenerySway(3.2, period: 4.6)
                    .position(x: geo.x(0.135), y: geo.under(22) - geo.u(46))

                SceneryFlowerPlant(height: geo.u(76), stemColor: stem,
                                   leafColor: grassDeep, petalColor: daisy,
                                   coreColor: pollen, petals: 8)
                    .frame(width: geo.u(54), height: geo.u(76), alignment: .bottom)
                    .scenerySway(3.6, period: 5.4, delay: 1.1)
                    .position(x: geo.x(0.885), y: geo.under(16) - geo.u(38))
            }

            SceneryButterfly(width: geo.u(24), wing: daisy, wingDeep: character.color)
                .position(x: -geo.u(30), y: geo.y(0.52))
                .sceneryDrift(dx: geo.size.width + geo.u(70), dy: -geo.u(40), period: 24)

            SceneryButterfly(width: geo.u(19), wing: character.color,
                             wingDeep: character.deepColor)
                .position(x: geo.size.width + geo.u(30), y: geo.y(0.44))
                .sceneryDrift(dx: -(geo.size.width + geo.u(70)), dy: geo.u(52),
                              period: 31, delay: 5)

            // Dandelion seeds on the same breeze.
            ForEach(0..<4, id: \.self) { index in
                SceneryFlake(diameter: geo.u(6))
                    .position(x: geo.x(0.2 + CGFloat(index) * 0.2), y: geo.under(-10))
                    .sceneryDrift(dx: geo.u(90 + CGFloat(index) * 30),
                                  dy: -geo.u(50 + CGFloat(index % 3) * 30),
                                  period: 19 + Double(index) * 3,
                                  delay: Double(index) * 3.5)
            }
        }
    }
}

// MARK: - Dog: the back garden

private struct GardenScene: View {
    let character: AnimalCharacter
    let geo: SceneGeometry
    let showsMotion: Bool

    private let skyTop = Color(red: 0.58, green: 0.86, blue: 0.93)
    private let skyLow = Color(red: 0.93, green: 0.98, blue: 0.96)
    private let lawn = Color(red: 0.46, green: 0.73, blue: 0.36)
    private let lawnDeep = Color(red: 0.29, green: 0.55, blue: 0.24)
    private let lawnLight = Color(red: 0.62, green: 0.84, blue: 0.44)
    private let hedge = Color(red: 0.22, green: 0.47, blue: 0.26)
    private let hedgeLight = Color(red: 0.33, green: 0.60, blue: 0.31)
    private let timber = Color(red: 0.94, green: 0.96, blue: 0.94)
    private let sunflower = Color(red: 0.99, green: 0.82, blue: 0.28)

    var body: some View {
        ZStack {
            still.drawingGroup()
            if showsMotion { motion }
        }
    }

    private var still: some View {
        ZStack {
            sky
            boundary
            shore
            beds
        }
    }

    private var sky: some View {
        ZStack {
            LinearGradient(colors: [skyTop, skyLow], startPoint: .top, endPoint: .bottom)

            ScenerySun(diameter: geo.u(66),
                       core: Color(red: 1.0, green: 0.96, blue: 0.74).opacity(0.82),
                       halo: character.tintColor)
                .position(x: geo.x(0.82), y: geo.y(0.14))
        }
    }

    private var boundary: some View {
        ZStack {
            // The neighbours' trees over the fence, then the hedge, then the
            // fence itself: three bands of depth for the price of three shapes.
            ForEach(0..<5, id: \.self) { index in
                let width = geo.u(96 + CGFloat(index % 3) * 26)
                let height = geo.u(104 + CGFloat(index % 3) * 24)
                Planted(x: geo.x(0.08 + CGFloat(index) * 0.22),
                        footY: geo.horizon - geo.u(18), width: width, height: height) {
                    // Hazed as one piece rather than lobe by lobe: fading the
                    // parts separately shows every seam in the crown.
                    SceneryCanopyTree(width: width, height: height,
                                      crown: hedge, crownLight: hedgeLight,
                                      trunk: Color(red: 0.45, green: 0.34, blue: 0.22))
                        .opacity(0.55)
                }
            }

            SceneryFence(width: geo.size.width * 1.05, height: geo.u(78),
                         pickets: 22, color: timber,
                         shade: character.color.opacity(0.75))
                .position(x: geo.x(0.5), y: geo.horizon - geo.u(28))

            ForEach(0..<6, id: \.self) { index in
                let width = geo.u(86 + CGFloat(index % 3) * 24)
                let height = geo.u(42 + CGFloat(index % 3) * 12)
                Planted(x: geo.x(0.02 + CGFloat(index) * 0.20),
                        footY: geo.under(8), width: width, height: height) {
                    SceneryBush(width: width, height: height,
                                color: hedge, light: hedgeLight)
                }
            }

            Rectangle()
                .fill(LinearGradient(colors: [lawn, lawnDeep],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: geo.size.width, height: geo.floorHeight)
                .position(x: geo.x(0.5), y: geo.floorCenter)

            // Mowing stripes, barely there.
            ForEach(0..<5, id: \.self) { index in
                Ellipse()
                    .fill(lawnLight.opacity(0.20))
                    .frame(width: geo.size.width * 0.34, height: geo.u(22))
                    .position(x: geo.x(0.1 + CGFloat(index) * 0.2),
                              y: geo.under(10 + CGFloat(index % 2) * 26))
            }
        }
    }

    private var shore: some View {
        ZStack {
            SceneryGroundPatch(width: geo.groundWidth, height: geo.groundDepth,
                               crownColor: lawnLight,
                               earthColor: Color(red: 0.36, green: 0.27, blue: 0.16),
                               rimColor: Color(red: 0.74, green: 0.90, blue: 0.54))
                .position(geo.groundCenter)

            ForEach(0..<5, id: \.self) { index in
                let spot = geo.beside(index.isMultiple(of: 2) ? -1 : 1,
                                      step: CGFloat(index / 2))
                Planted(x: spot.x, footY: spot.y,
                        width: geo.u(30), height: geo.u(18 + CGFloat(index % 3) * 7)) {
                    SceneryTuft(width: geo.u(30), height: geo.u(18 + CGFloat(index % 3) * 7),
                                color: lawnDeep, light: lawn, blades: 6)
                }
            }

            // The dog's ball, in the dog's own colour, and a bone beside it.
            Circle()
                .fill(RadialGradient(colors: [character.tintColor, character.color],
                                     center: .topLeading, startRadius: 1,
                                     endRadius: geo.u(30)))
                .frame(width: geo.u(26), height: geo.u(26))
                .overlay {
                    Capsule().fill(Color.white.opacity(0.8))
                        .frame(width: geo.u(24), height: geo.u(5))
                        .rotationEffect(.degrees(-18))
                }
                .position(geo.beside(-1, step: 3))

            HStack(spacing: -geo.u(3)) {
                Circle().frame(width: geo.u(9), height: geo.u(9))
                Capsule().frame(width: geo.u(20), height: geo.u(7))
                Circle().frame(width: geo.u(9), height: geo.u(9))
            }
            .foregroundStyle(Color(red: 0.98, green: 0.96, blue: 0.90))
            .rotationEffect(.degrees(-12))
            .position(geo.beside(1, step: 3))

            LoungerShadow(geo: geo)
        }
    }

    private var beds: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                Planted(x: geo.x(0.045 + CGFloat(index) * 0.04),
                        footY: geo.under(20 + CGFloat(index) * 9),
                        width: geo.u(62), height: geo.u(96 + CGFloat(index) * 14)) {
                    SceneryFlowerPlant(height: geo.u(96 + CGFloat(index) * 14),
                                       stemColor: lawnDeep, leafColor: hedge,
                                       petalColor: sunflower,
                                       coreColor: Color(red: 0.42, green: 0.26, blue: 0.10),
                                       petals: 9, lean: Double(index) * 5 - 5)
                }
            }

            Planted(x: geo.x(0.955), footY: geo.under(18),
                    width: geo.u(58), height: geo.u(84)) {
                SceneryFlowerPlant(height: geo.u(84), stemColor: lawnDeep,
                                   leafColor: hedge,
                                   petalColor: character.tintColor,
                                   coreColor: character.deepColor,
                                   petals: 6, lean: -5)
            }

            Planted(x: geo.x(0.88), footY: geo.under(12),
                    width: geo.u(38), height: geo.u(56)) {
                SceneryTuft(width: geo.u(38), height: geo.u(56),
                            color: lawnDeep, light: lawnLight, blades: 7)
            }

            // Stepping stones leading off to the side of the lawn.
            ForEach(0..<4, id: \.self) { index in
                Ellipse()
                    .fill(Color(red: 0.80, green: 0.79, blue: 0.74).opacity(0.85))
                    .frame(width: geo.u(30 + CGFloat(index) * 5), height: geo.u(13))
                    .position(x: geo.x(0.24 - CGFloat(index) * 0.045),
                              y: geo.under(18 + CGFloat(index) * 15))
            }
        }
    }

    private var motion: some View {
        ZStack {
            SceneryCloud(width: geo.u(96))
                .position(x: -geo.u(72), y: geo.y(0.16))
                .sceneryDrift(dx: geo.size.width + geo.u(210), period: 112)

            SceneryCloud(width: geo.u(70), opacity: 0.58)
                .position(x: -geo.u(54), y: geo.y(0.30))
                .sceneryDrift(dx: geo.size.width + geo.u(170), period: 152, delay: 18)

            SceneryFlowerPlant(height: geo.u(104), stemColor: lawnDeep,
                               leafColor: hedge, petalColor: sunflower,
                               coreColor: Color(red: 0.42, green: 0.26, blue: 0.10),
                               petals: 9)
                .frame(width: geo.u(68), height: geo.u(104), alignment: .bottom)
                .scenerySway(2.8, period: 5.0)
                .position(x: geo.x(0.155), y: geo.under(22) - geo.u(52))

            SceneryTuft(width: geo.u(34), height: geo.u(52),
                        color: lawnDeep, light: lawnLight, blades: 6)
                .frame(width: geo.u(34), height: geo.u(52), alignment: .bottom)
                .scenerySway(3.4, period: 4.4, delay: 1.3)
                .position(x: geo.x(0.93), y: geo.under(10) - geo.u(26))

            SceneryButterfly(width: geo.u(21), wing: Color.white,
                             wingDeep: character.color)
                .position(x: -geo.u(30), y: geo.y(0.48))
                .sceneryDrift(dx: geo.size.width + geo.u(70), dy: -geo.u(34), period: 27)

            SkyFlight(geo: geo, count: 3, span: 18, topShare: 0.21,
                      color: hedge.opacity(0.45), period: 23)

            SkyFlight(geo: geo, count: 2, span: 12, topShare: 0.10,
                      color: hedge.opacity(0.28), period: 38, rightwards: false)

            SkyWisp(geo: geo, heightShare: 0.34, lengthShare: 0.38,
                    opacity: 0.28, period: 160, delay: 26)

            // A second butterfly working the far side of the lawn.
            SceneryButterfly(width: geo.u(17), wing: character.tintColor,
                             wingDeep: character.deepColor)
                .position(x: geo.size.width + geo.u(28), y: geo.y(0.38))
                .sceneryDrift(dx: -(geo.size.width + geo.u(66)), dy: geo.u(46),
                              period: 33, delay: 8)
        }
    }
}

// MARK: - Lion: the savannah

private struct SavannahScene: View {
    let character: AnimalCharacter
    let geo: SceneGeometry
    let showsMotion: Bool

    private let skyTop = Color(red: 0.98, green: 0.66, blue: 0.32)
    private let skyLow = Color(red: 1.0, green: 0.93, blue: 0.74)
    private let earth = Color(red: 0.87, green: 0.71, blue: 0.39)
    private let earthDeep = Color(red: 0.53, green: 0.38, blue: 0.18)
    private let dryGrass = Color(red: 0.83, green: 0.68, blue: 0.32)
    private let dryGrassLight = Color(red: 0.94, green: 0.83, blue: 0.48)
    private let bark = Color(red: 0.36, green: 0.26, blue: 0.16)
    private let acaciaCrown = Color(red: 0.32, green: 0.44, blue: 0.24)

    var body: some View {
        ZStack {
            still.drawingGroup()
            if showsMotion { motion }
        }
    }

    private var still: some View {
        ZStack {
            sky
            plain
            shore
            grasses
        }
    }

    private var sky: some View {
        ZStack {
            LinearGradient(colors: [skyTop, skyLow], startPoint: .top, endPoint: .bottom)

            ScenerySun(diameter: geo.u(104),
                       core: Color(red: 1.0, green: 0.88, blue: 0.44).opacity(0.9),
                       halo: Color(red: 1.0, green: 0.78, blue: 0.36))
                .position(x: geo.x(0.74), y: geo.y(0.23))

            // Escarpments on the far side of the plain: three bands, each one
            // warmer and darker than the one behind it, which is the only thing
            // that stops a savannah reading as one flat wash of orange.
            Ellipse()
                .fill(Color(red: 0.86, green: 0.55, blue: 0.30).opacity(0.42))
                .frame(width: geo.x(1.1), height: geo.u(118))
                .position(x: geo.x(0.34), y: geo.horizon - geo.u(58))
            Ellipse()
                .fill(character.deepColor.opacity(0.26))
                .frame(width: geo.x(0.82), height: geo.u(86))
                .position(x: geo.x(0.86), y: geo.horizon - geo.u(38))
            Ellipse()
                .fill(character.color.opacity(0.34))
                .frame(width: geo.x(1.2), height: geo.u(74))
                .position(x: geo.x(0.30), y: geo.horizon - geo.u(18))
        }
    }

    private var plain: some View {
        ZStack {
            // Two hazy acacias on the far plain and one full-grown tree near
            // the eye, which is what gives the flat any depth at all.
            ForEach(0..<2, id: \.self) { index in
                let width = geo.u(96 + CGFloat(index) * 26)
                let height = geo.u(78 + CGFloat(index) * 20)
                Planted(x: geo.x(0.42 + CGFloat(index) * 0.34),
                        footY: geo.horizon - geo.u(4), width: width, height: height) {
                    SceneryAcacia(width: width, height: height,
                                  crown: acaciaCrown,
                                  crownLight: acaciaCrown.opacity(0.66),
                                  trunk: bark)
                        .opacity(0.45)
                }
            }

            Rectangle()
                .fill(LinearGradient(colors: [earth, earthDeep],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: geo.size.width, height: geo.floorHeight)
                .position(x: geo.x(0.5), y: geo.floorCenter)

            Ellipse()
                .fill(dryGrassLight.opacity(0.55))
                .frame(width: geo.size.width * 1.2, height: geo.u(46))
                .position(x: geo.x(0.5), y: geo.horizon)

            // The waterhole: a pan of sky lying in the flat, ringed by the mud
            // it has been trodden out of.
            ZStack {
                Ellipse()
                    .fill(Color(red: 0.62, green: 0.50, blue: 0.28))
                    .frame(width: geo.u(196), height: geo.u(60))
                    .blur(radius: geo.u(3))
                Ellipse()
                    .fill(LinearGradient(colors: [Color(red: 0.52, green: 0.74, blue: 0.78),
                                                  Color(red: 0.24, green: 0.44, blue: 0.52)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: geo.u(162), height: geo.u(44))
                Capsule()
                    .fill(Color.white.opacity(0.34))
                    .frame(width: geo.u(66), height: geo.u(4))
                    .offset(x: -geo.u(20), y: -geo.u(7))
                Capsule()
                    .fill(Color.white.opacity(0.22))
                    .frame(width: geo.u(42), height: geo.u(3))
                    .offset(x: geo.u(28), y: geo.u(6))
            }
            .position(x: geo.x(0.19), y: geo.under(52))

            // The near trees stand in front of the flat, not behind it.
            Planted(x: geo.x(0.13), footY: geo.under(14),
                    width: geo.u(210), height: geo.u(176)) {
                SceneryAcacia(width: geo.u(210), height: geo.u(176),
                              crown: acaciaCrown, crownLight: acaciaCrown.opacity(0.68),
                              trunk: bark)
            }

            Planted(x: geo.x(0.93), footY: geo.under(8),
                    width: geo.u(122), height: geo.u(102)) {
                SceneryAcacia(width: geo.u(122), height: geo.u(102),
                              crown: acaciaCrown,
                              crownLight: acaciaCrown.opacity(0.68),
                              trunk: bark)
                    .opacity(0.82)
            }

            Planted(x: geo.x(0.86), footY: geo.under(34),
                    width: geo.u(92), height: geo.u(44)) {
                SceneryRock(width: geo.u(92), height: geo.u(44),
                            color: Color(red: 0.58, green: 0.50, blue: 0.40),
                            light: Color(red: 0.78, green: 0.70, blue: 0.58))
            }
        }
    }

    private var shore: some View {
        ZStack {
            SceneryGroundPatch(width: geo.groundWidth, height: geo.groundDepth,
                               crownColor: Color(red: 0.92, green: 0.80, blue: 0.48),
                               earthColor: Color(red: 0.55, green: 0.40, blue: 0.20),
                               rimColor: Color(red: 0.98, green: 0.90, blue: 0.64))
                .position(geo.groundCenter)

            ForEach(0..<6, id: \.self) { index in
                let spot = geo.beside(index.isMultiple(of: 2) ? -1 : 1,
                                      step: CGFloat(index / 2))
                Planted(x: spot.x, footY: spot.y,
                        width: geo.u(34), height: geo.u(22 + CGFloat(index % 3) * 8)) {
                    SceneryTuft(width: geo.u(34), height: geo.u(22 + CGFloat(index % 3) * 8),
                                color: dryGrass, light: dryGrassLight, blades: 9)
                }
            }

            ForEach(0..<4, id: \.self) { index in
                let width = geo.u(14 + CGFloat(index) * 6)
                let height = geo.u(8 + CGFloat(index % 2) * 4)
                Planted(x: geo.beside(index.isMultiple(of: 2) ? -1 : 1,
                                              step: 2.1 + CGFloat(index / 2) * 0.8).x,
                        footY: geo.beside(index.isMultiple(of: 2) ? -1 : 1,
                                          step: 2.1 + CGFloat(index / 2) * 0.8).y,
                        width: width, height: height) {
                    SceneryRock(width: width, height: height,
                                color: Color(red: 0.62, green: 0.54, blue: 0.42),
                                light: Color(red: 0.82, green: 0.74, blue: 0.60))
                }
            }

            LoungerShadow(geo: geo, opacity: 0.20)
        }
    }

    private var grasses: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                Planted(x: geo.x(0.04 + CGFloat(index) * 0.045),
                        footY: geo.under(22 + CGFloat(index) * 10),
                        width: geo.u(52), height: geo.u(96 + CGFloat(index) * 16)) {
                    SceneryTuft(width: geo.u(52), height: geo.u(96 + CGFloat(index) * 16),
                                color: dryGrass, light: dryGrassLight, blades: 9)
                }
            }

            ForEach(0..<2, id: \.self) { index in
                Planted(x: geo.x(0.955 + CGFloat(index) * 0.03),
                        footY: geo.under(16 + CGFloat(index) * 12),
                        width: geo.u(46), height: geo.u(80 + CGFloat(index) * 18)) {
                    SceneryTuft(width: geo.u(46), height: geo.u(80 + CGFloat(index) * 18),
                                color: dryGrass, light: dryGrassLight, blades: 8)
                }
            }
        }
    }

    private var motion: some View {
        ZStack {
            SkyFlight(geo: geo, count: 3, span: 21, topShare: 0.16,
                      color: bark.opacity(0.38), period: 28)

            // A pair riding a thermal the other way, high and slow.
            SkyFlight(geo: geo, count: 2, span: 26, topShare: 0.07,
                      color: bark.opacity(0.26), period: 52, rightwards: false)

            SkyWisp(geo: geo, heightShare: 0.30, lengthShare: 0.56,
                    color: Color(red: 1.0, green: 0.90, blue: 0.72),
                    opacity: 0.32, period: 190)

            SceneryTuft(width: geo.u(58), height: geo.u(112),
                        color: dryGrass, light: dryGrassLight, blades: 9)
                .frame(width: geo.u(58), height: geo.u(112), alignment: .bottom)
                .scenerySway(3.6, period: 4.8)
                .position(x: geo.x(0.145), y: geo.under(24) - geo.u(56))

            SceneryTuft(width: geo.u(48), height: geo.u(92),
                        color: dryGrass, light: dryGrassLight, blades: 8)
                .frame(width: geo.u(48), height: geo.u(92), alignment: .bottom)
                .scenerySway(4.0, period: 5.6, delay: 1.5)
                .position(x: geo.x(0.9), y: geo.under(18) - geo.u(46))

            // Dust carried across the flat on the same wind.
            ForEach(0..<3, id: \.self) { index in
                Ellipse()
                    .fill(Color(red: 0.96, green: 0.88, blue: 0.68).opacity(0.4))
                    .frame(width: geo.u(22 + CGFloat(index) * 8), height: geo.u(6))
                    .position(x: -geo.u(30), y: geo.under(12 + CGFloat(index) * 18))
                    .sceneryDrift(dx: geo.size.width + geo.u(60), dy: -geo.u(8),
                                  period: 17 + Double(index) * 5, delay: Double(index) * 4)
            }
        }
    }
}

// MARK: - Octopus: the reef floor

private struct ReefScene: View {
    let character: AnimalCharacter
    let geo: SceneGeometry
    let showsMotion: Bool

    private let waterTop = Color(red: 0.36, green: 0.46, blue: 0.82)
    private let waterDeep = Color(red: 0.11, green: 0.09, blue: 0.32)
    private let sand = Color(red: 0.84, green: 0.78, blue: 0.92)
    private let sandDeep = Color(red: 0.46, green: 0.36, blue: 0.62)
    private let weed = Color(red: 0.26, green: 0.54, blue: 0.48)
    private let weedLight = Color(red: 0.40, green: 0.72, blue: 0.60)
    private let coral = Color(red: 0.96, green: 0.52, blue: 0.66)

    var body: some View {
        ZStack {
            still.drawingGroup()
            if showsMotion { motion }
        }
    }

    private var still: some View {
        ZStack {
            open
            bed
            shore
            garden
        }
    }

    private var open: some View {
        ZStack {
            LinearGradient(colors: [waterTop, waterDeep],
                           startPoint: .top, endPoint: .bottom)

            Ellipse()
                .fill(character.color.opacity(0.22))
                .frame(width: geo.size.width * 1.2, height: geo.y(0.5))
                .position(x: geo.x(0.5), y: geo.y(0.06))
                .blur(radius: geo.u(30))

            // Shafts of light coming down through the surface.
            ForEach(0..<3, id: \.self) { index in
                Capsule()
                    .fill(LinearGradient(colors: [character.tintColor.opacity(0.34),
                                                  .clear],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: geo.u(52 + CGFloat(index) * 16), height: geo.y(0.72))
                    .rotationEffect(.degrees(Double(index) * 9 - 12))
                    .position(x: geo.x(0.24 + CGFloat(index) * 0.29), y: geo.y(0.30))
                    .blur(radius: geo.u(12))
            }
        }
    }

    private var bed: some View {
        ZStack {
            Ellipse()
                .fill(sandDeep)
                .frame(width: geo.size.width * 1.4, height: geo.u(110))
                .position(x: geo.x(0.5), y: geo.under(20))

            Rectangle()
                .fill(LinearGradient(colors: [sandDeep, Color(red: 0.30, green: 0.22, blue: 0.44)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: geo.size.width, height: geo.floorHeight)
                .position(x: geo.x(0.5), y: geo.floorCenter)

            Ellipse()
                .fill(sand.opacity(0.45))
                .frame(width: geo.size.width * 1.15, height: geo.u(42))
                .position(x: geo.x(0.5), y: geo.horizon)

            ForEach(0..<5, id: \.self) { index in
                let width = geo.u(74 + CGFloat(index % 3) * 34)
                let height = geo.u(26 + CGFloat(index % 3) * 12)
                Planted(x: geo.x(0.07 + CGFloat(index) * 0.22),
                        footY: geo.under(14), width: width, height: height) {
                    SceneryRock(width: width, height: height,
                                color: sandDeep, light: sand.opacity(0.75))
                }
            }
        }
    }

    private var shore: some View {
        ZStack {
            // Kept a shade under the open sand behind it: a ledge this deep
            // glares if it is painted in the lightest colour in the scene.
            SceneryGroundPatch(width: geo.groundWidth, height: geo.groundDepth,
                               crownColor: Color(red: 0.72, green: 0.65, blue: 0.84),
                               earthColor: sandDeep,
                               rimColor: Color(red: 0.88, green: 0.83, blue: 0.96))
                .position(geo.groundCenter)

            ForEach(0..<4, id: \.self) { index in
                let spot = geo.beside(index.isMultiple(of: 2) ? -1 : 1,
                                      step: CGFloat(index / 2))
                Planted(x: spot.x, footY: spot.y,
                        width: geo.u(40), height: geo.u(24 + CGFloat(index % 3) * 8)) {
                    SceneryCoral(width: geo.u(40),
                                 height: geo.u(24 + CGFloat(index % 3) * 8),
                                 color: coral.opacity(0.8), light: character.tintColor,
                                 branches: 5)
                }
            }

            SceneryStarfish(width: geo.u(30), color: coral,
                            light: Color(red: 1.0, green: 0.80, blue: 0.84))
                .rotationEffect(.degrees(14))
                .position(geo.beside(-1, step: 3))

            SceneryShell(width: geo.u(30), color: Color(red: 0.98, green: 0.93, blue: 0.86),
                         line: Color(red: 0.86, green: 0.72, blue: 0.78))
                .rotationEffect(.degrees(-10))
                .position(geo.beside(1, step: 3))

            LoungerShadow(geo: geo, opacity: 0.22)
        }
    }

    private var garden: some View {
        ZStack {
            SceneryCoral(width: geo.u(96), height: geo.u(104),
                         color: coral, light: character.color, branches: 6)
                .position(x: geo.x(0.075), y: geo.under(-34))

            SceneryAnemone(width: geo.u(76), height: geo.u(58),
                           color: character.color, tip: character.tintColor)
                .position(x: geo.x(0.185), y: geo.under(10))

            SceneryCoral(width: geo.u(72), height: geo.u(78),
                         color: character.deepColor, light: coral.opacity(0.8),
                         branches: 5)
                .position(x: geo.x(0.94), y: geo.under(-18))

            SceneryStarfish(width: geo.u(26),
                            color: character.color, light: character.tintColor)
                .rotationEffect(.degrees(-22))
                .position(x: geo.x(0.30), y: geo.under(38))

            SceneryShell(width: geo.u(24), color: Color(red: 0.96, green: 0.90, blue: 0.98),
                         line: character.deepColor.opacity(0.6))
                .rotationEffect(.degrees(12))
                .position(x: geo.x(0.72), y: geo.under(48))
        }
    }

    private var motion: some View {
        ZStack {
            // Kelp leaning in the current.
            ForEach(0..<3, id: \.self) { index in
                let height = geo.u(150 + CGFloat(index % 2) * 40)
                SceneryKelp(width: geo.u(30), height: height,
                            color: weed, light: weedLight)
                    .frame(width: geo.u(30), height: height, alignment: .bottom)
                    .scenerySway(4.4, period: 6.0 + Double(index), delay: Double(index) * 1.2)
                    .position(x: geo.x(index == 2 ? 0.885 : 0.11 + CGFloat(index) * 0.08),
                              y: geo.under(10) - height * 0.5)
            }

            SceneryAnemone(width: geo.u(56), height: geo.u(44),
                           color: coral, tip: Color(red: 1.0, green: 0.86, blue: 0.90))
                .frame(width: geo.u(56), height: geo.u(44), alignment: .bottom)
                .scenerySway(3.0, period: 4.6, delay: 0.7)
                .position(x: geo.x(0.80), y: geo.under(22) - geo.u(22))

            // Bubbles leaving the reef and rising out of the scene.
            ForEach(0..<6, id: \.self) { index in
                SceneryBubble(diameter: geo.u(7 + CGFloat(index % 3) * 4))
                    .position(x: geo.x(0.12 + CGFloat(index) * 0.15),
                              y: geo.under(30))
                    .sceneryDrift(dx: geo.u(CGFloat(index % 3) * 14 - 12),
                                  dy: -(geo.size.height + geo.u(60)),
                                  period: 13 + Double(index % 4) * 3,
                                  delay: Double(index) * 2.1)
            }

            SceneryFish(length: geo.u(40), color: character.tintColor,
                        belly: Color.white, swimsRight: true)
                .position(x: -geo.u(50), y: geo.y(0.42))
                .sceneryDrift(dx: geo.size.width + geo.u(110), dy: -geo.u(24), period: 22)

            SceneryFish(length: geo.u(30), color: coral, belly: Color.white)
                .position(x: geo.size.width + geo.u(40), y: geo.y(0.58))
                .sceneryDrift(dx: -(geo.size.width + geo.u(90)), dy: geo.u(18),
                              period: 26, delay: 6)

            SceneryFish(length: geo.u(22), color: character.color,
                        belly: character.tintColor, swimsRight: true)
                .position(x: -geo.u(36), y: geo.y(0.30))
                .sceneryDrift(dx: geo.size.width + geo.u(80), dy: geo.u(30),
                              period: 31, delay: 12)

            // A shoal higher up in the water, small and pale enough to read as
            // distance rather than as three more things to look at.
            ForEach(0..<3, id: \.self) { index in
                SceneryFish(length: geo.u(14 + CGFloat(index % 2) * 4),
                            color: character.tintColor.opacity(0.55),
                            belly: Color.white.opacity(0.5))
                    .position(x: geo.size.width + geo.u(30 + CGFloat(index) * 26),
                              y: geo.y(0.18 + CGFloat(index) * 0.05))
                    .sceneryDrift(dx: -(geo.size.width + geo.u(120)), dy: geo.u(20),
                                  period: 38 + Double(index) * 5,
                                  delay: Double(index) * 3)
            }
        }
    }
}

// MARK: - Crab: the shore

private struct BeachScene: View {
    let character: AnimalCharacter
    let geo: SceneGeometry
    let showsMotion: Bool

    private let skyTop = Color(red: 0.55, green: 0.83, blue: 0.98)
    private let skyLow = Color(red: 1.0, green: 0.93, blue: 0.82)
    private let seaTop = Color(red: 0.29, green: 0.72, blue: 0.80)
    private let seaDeep = Color(red: 0.10, green: 0.48, blue: 0.66)
    private let sand = Color(red: 0.98, green: 0.90, blue: 0.70)
    private let sandDeep = Color(red: 0.85, green: 0.72, blue: 0.48)
    private let palmGreen = Color(red: 0.24, green: 0.56, blue: 0.32)
    private let bark = Color(red: 0.52, green: 0.38, blue: 0.22)

    /// The sea's own horizon sits well above the shore, so the beach itself is
    /// what the lounger stands on.
    private var seaTopY: CGFloat { geo.y(0.56) }

    var body: some View {
        ZStack {
            still.drawingGroup()
            if showsMotion { motion }
        }
    }

    private var still: some View {
        ZStack {
            sky
            sea
            beach
            shore
        }
    }

    private var sky: some View {
        ZStack {
            LinearGradient(colors: [skyTop, skyLow], startPoint: .top, endPoint: .bottom)

            ScenerySun(diameter: geo.u(80),
                       core: Color(red: 1.0, green: 0.93, blue: 0.58).opacity(0.85),
                       halo: Color(red: 1.0, green: 0.86, blue: 0.62))
                .position(x: geo.x(0.19), y: geo.y(0.15))
        }
    }

    private var sea: some View {
        ZStack {
            Rectangle()
                .fill(LinearGradient(colors: [seaDeep, seaTop],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: geo.size.width, height: geo.horizon - seaTopY)
                .position(x: geo.x(0.5), y: (seaTopY + geo.horizon) * 0.5)

            ForEach(0..<5, id: \.self) { index in
                Capsule()
                    .fill(Color.white.opacity(0.26))
                    .frame(width: geo.u(70 + CGFloat(index % 3) * 20), height: geo.u(5))
                    .position(x: geo.x(0.08 + CGFloat(index) * 0.21),
                              y: seaTopY + geo.u(14 + CGFloat(index % 3) * 20))
            }

            // Wet sand, then the dry beach.
            Ellipse()
                .fill(sandDeep.opacity(0.9))
                .frame(width: geo.size.width * 1.3, height: geo.u(54))
                .position(x: geo.x(0.5), y: geo.horizon)
        }
    }

    private var beach: some View {
        ZStack {
            Rectangle()
                .fill(LinearGradient(colors: [sand, sandDeep],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: geo.size.width, height: geo.floorHeight)
                .position(x: geo.x(0.5), y: geo.floorCenter)

            Ellipse()
                .fill(Color.white.opacity(0.35))
                .frame(width: geo.size.width * 1.2, height: geo.u(26))
                .position(x: geo.x(0.5), y: geo.horizon + geo.u(6))
                .blur(radius: geo.u(4))

            // The dune the palm grows out of.
            Ellipse()
                .fill(sandDeep.opacity(0.55))
                .frame(width: geo.u(210), height: geo.u(70))
                .position(x: geo.x(0.09), y: geo.under(34))

            ForEach(0..<3, id: \.self) { index in
                let width = geo.u(44 + CGFloat(index % 2) * 14)
                let height = geo.u(48 + CGFloat(index % 3) * 16)
                Planted(x: geo.x(0.90 + CGFloat(index) * 0.05),
                        footY: geo.under(16 + CGFloat(index) * 8),
                        width: width, height: height) {
                    SceneryTuft(width: width, height: height,
                                color: palmGreen.opacity(0.85),
                                light: Color(red: 0.56, green: 0.76, blue: 0.44),
                                blades: 11)
                }
            }

            // Shells, a starfish and a bucket left out on the open sand, so the
            // band between the surf and the lounger is not bare.
            SceneryShell(width: geo.u(26), color: Color(red: 1.0, green: 0.96, blue: 0.92),
                         line: Color(red: 0.88, green: 0.66, blue: 0.60))
                .rotationEffect(.degrees(-14))
                .position(x: geo.x(0.30), y: geo.under(20))

            SceneryShell(width: geo.u(20), color: Color(red: 0.99, green: 0.93, blue: 0.86),
                         line: Color(red: 0.86, green: 0.72, blue: 0.62))
                .rotationEffect(.degrees(18))
                .position(x: geo.x(0.70), y: geo.under(14))

            SceneryStarfish(width: geo.u(24), color: character.color.opacity(0.85),
                            light: Color(red: 1.0, green: 0.78, blue: 0.68))
                .rotationEffect(.degrees(24))
                .position(x: geo.x(0.63), y: geo.under(34))

            // The pail and its spade, in the crab's own red.
            ZStack(alignment: .bottom) {
                Capsule()
                    .fill(Color(red: 0.99, green: 0.86, blue: 0.34))
                    .frame(width: geo.u(5), height: geo.u(48))
                    .rotationEffect(.degrees(19), anchor: .bottom)
                    .offset(x: geo.u(19))

                SceneryPailShape()
                    .fill(LinearGradient(colors: [character.color, character.deepColor],
                                         startPoint: .topLeading,
                                         endPoint: .bottomTrailing))
                    .frame(width: geo.u(32), height: geo.u(28))
                    .overlay(alignment: .top) {
                        Capsule()
                            .fill(character.tintColor)
                            .frame(width: geo.u(34), height: geo.u(5))
                            .offset(y: -geo.u(1))
                    }
                    .overlay(alignment: .top) {
                        Circle()
                            .strokeBorder(Color(red: 0.99, green: 0.86, blue: 0.34),
                                          lineWidth: geo.u(2.5))
                            .frame(width: geo.u(26), height: geo.u(26))
                            .offset(y: -geo.u(11))
                    }
            }
            .frame(width: geo.u(60), height: geo.u(52), alignment: .bottom)
            .position(x: geo.x(0.79), y: geo.under(26) - geo.u(26))

            ForEach(0..<5, id: \.self) { index in
                Ellipse()
                    .fill(sandDeep.opacity(0.5))
                    .frame(width: geo.u(16), height: geo.u(10))
                    .position(x: geo.x(0.36 + CGFloat(index) * 0.055),
                              y: geo.under(38 + CGFloat(index % 2) * 12))
            }
        }
    }

    private var shore: some View {
        ZStack {
            SceneryGroundPatch(width: geo.groundWidth, height: geo.groundDepth,
                               crownColor: Color(red: 1.0, green: 0.94, blue: 0.78),
                               earthColor: sandDeep,
                               rimColor: Color(red: 1.0, green: 0.97, blue: 0.86))
                .position(geo.groundCenter)

            SceneryStarfish(width: geo.u(32), color: character.color,
                            light: character.tintColor)
                .rotationEffect(.degrees(-16))
                .position(geo.beside(-1, step: 3))

            SceneryShell(width: geo.u(32), color: Color(red: 1.0, green: 0.95, blue: 0.90),
                         line: character.color.opacity(0.7))
                .rotationEffect(.degrees(12))
                .position(geo.beside(1, step: 3))

            // The beach ball, in the crab's own red.
            Circle()
                .fill(RadialGradient(colors: [Color.white, character.color],
                                     center: .topLeading, startRadius: 1,
                                     endRadius: geo.u(34)))
                .frame(width: geo.u(30), height: geo.u(30))
                .overlay {
                    Capsule().fill(Color.white.opacity(0.85))
                        .frame(width: geo.u(28), height: geo.u(6))
                        .rotationEffect(.degrees(28))
                }
                .position(geo.beside(1, step: 3.4))

            // Driftwood and pebbles along the tide line.
            ForEach(0..<4, id: \.self) { index in
                Ellipse()
                    .fill(Color(red: 0.76, green: 0.70, blue: 0.62).opacity(0.9))
                    .frame(width: geo.u(14 + CGFloat(index) * 4), height: geo.u(8))
                    .position(x: geo.x(0.26 + CGFloat(index) * 0.13),
                              y: geo.under(10 + CGFloat(index % 2) * 9))
            }

            Capsule()
                .fill(bark.opacity(0.8))
                .frame(width: geo.u(84), height: geo.u(13))
                .rotationEffect(.degrees(-7))
                .position(x: geo.x(0.235), y: geo.under(46))

            LoungerShadow(geo: geo, opacity: 0.14)
        }
    }

    private var motion: some View {
        ZStack {
            SceneryCloud(width: geo.u(92))
                .position(x: -geo.u(70), y: geo.y(0.13))
                .sceneryDrift(dx: geo.size.width + geo.u(200), period: 108)

            SceneryCloud(width: geo.u(66), opacity: 0.58)
                .position(x: -geo.u(52), y: geo.y(0.28))
                .sceneryDrift(dx: geo.size.width + geo.u(160), period: 150, delay: 14)

            SceneryPalm(width: geo.u(200), height: geo.u(240),
                        frond: palmGreen,
                        frondLight: Color(red: 0.40, green: 0.70, blue: 0.38),
                        trunk: bark)
                .frame(width: geo.u(200), height: geo.u(240), alignment: .bottom)
                .scenerySway(1.6, period: 6.4)
                .position(x: geo.x(0.10), y: geo.under(28) - geo.u(120))

            // The surf, running up the wet sand and back.
            ForEach(0..<3, id: \.self) { index in
                Capsule()
                    .fill(Color.white.opacity(0.42 - Double(index) * 0.08))
                    .frame(width: geo.size.width * (0.5 - CGFloat(index) * 0.09),
                           height: geo.u(9))
                    .position(x: geo.x(0.28 + CGFloat(index) * 0.24),
                              y: geo.horizon + geo.u(2 + CGFloat(index) * 7))
                    .sceneryBob(dy: geo.u(4), period: 3.4 + Double(index) * 0.6,
                                delay: Double(index) * 0.5)
            }

            SkyFlight(geo: geo, count: 3, span: 23, topShare: 0.20,
                      color: Color(red: 0.34, green: 0.38, blue: 0.46).opacity(0.42),
                      period: 25)

            SkyFlight(geo: geo, count: 2, span: 14, topShare: 0.09,
                      color: Color(red: 0.34, green: 0.38, blue: 0.46).opacity(0.28),
                      period: 42, rightwards: false)

            SkyWisp(geo: geo, heightShare: 0.38, lengthShare: 0.46,
                    opacity: 0.26, period: 172, delay: 30)
        }
    }
}

// MARK: - Elephant: the zoo enclosure

private struct ZooScene: View {
    let character: AnimalCharacter
    let geo: SceneGeometry
    let showsMotion: Bool

    private let skyTop = Color(red: 0.64, green: 0.83, blue: 0.96)
    private let skyLow = Color(red: 0.95, green: 0.97, blue: 0.93)
    private let jungle = Color(red: 0.19, green: 0.44, blue: 0.28)
    private let jungleLight = Color(red: 0.30, green: 0.58, blue: 0.34)
    private let straw = Color(red: 0.87, green: 0.80, blue: 0.59)
    private let strawDeep = Color(red: 0.58, green: 0.50, blue: 0.32)
    private let timber = Color(red: 0.60, green: 0.44, blue: 0.27)
    private let timberDark = Color(red: 0.44, green: 0.31, blue: 0.18)

    var body: some View {
        ZStack {
            still.drawingGroup()
            if showsMotion { motion }
        }
    }

    private var still: some View {
        ZStack {
            sky
            enclosure
            shore
            props
        }
    }

    private var sky: some View {
        ZStack {
            LinearGradient(colors: [skyTop, skyLow], startPoint: .top, endPoint: .bottom)

            ScenerySun(diameter: geo.u(64),
                       core: Color(red: 1.0, green: 0.97, blue: 0.78).opacity(0.8),
                       halo: character.tintColor)
                .position(x: geo.x(0.81), y: geo.y(0.13))
        }
    }

    private var enclosure: some View {
        ZStack {
            ForEach(0..<6, id: \.self) { index in
                let width = geo.u(104 + CGFloat(index % 3) * 30)
                let height = geo.u(116 + CGFloat(index % 3) * 28)
                Planted(x: geo.x(0.04 + CGFloat(index) * 0.19),
                        footY: geo.horizon - geo.u(20), width: width, height: height) {
                    SceneryCanopyTree(width: width, height: height,
                                      crown: jungle, crownLight: jungleLight,
                                      trunk: timberDark)
                        .opacity(0.62)
                }
            }

            ForEach(0..<6, id: \.self) { index in
                let width = geo.u(94 + CGFloat(index % 3) * 26)
                let height = geo.u(46 + CGFloat(index % 3) * 14)
                Planted(x: geo.x(0.02 + CGFloat(index) * 0.20),
                        footY: geo.horizon - geo.u(2), width: width, height: height) {
                    SceneryBush(width: width, height: height,
                                color: jungle, light: jungleLight)
                }
            }

            // The enclosure rail: heavy horizontal timbers rather than pickets.
            ZStack {
                ForEach(0..<2, id: \.self) { index in
                    Capsule()
                        .fill(timber)
                        .frame(width: geo.size.width * 1.05, height: geo.u(11))
                        .position(x: geo.x(0.5),
                                  y: geo.horizon - geo.u(30 - CGFloat(index) * 18))
                }
                ForEach(0..<7, id: \.self) { index in
                    Capsule()
                        .fill(timberDark)
                        .frame(width: geo.u(13), height: geo.u(54))
                        .position(x: geo.x(0.03 + CGFloat(index) * 0.157),
                                  y: geo.horizon - geo.u(24))
                }
            }

            Rectangle()
                .fill(LinearGradient(colors: [straw, strawDeep],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: geo.size.width, height: geo.floorHeight)
                .position(x: geo.x(0.5), y: geo.floorCenter)

            Ellipse()
                .fill(Color(red: 0.94, green: 0.89, blue: 0.72).opacity(0.6))
                .frame(width: geo.size.width * 1.2, height: geo.u(38))
                .position(x: geo.x(0.5), y: geo.horizon + geo.u(2))

            // Loose straw kicked about the floor of the enclosure.
            ForEach(0..<16, id: \.self) { index in
                Capsule()
                    .fill(strawDeep.opacity(0.55))
                    .frame(width: geo.u(16 + CGFloat(index % 3) * 7), height: geo.u(3))
                    .rotationEffect(.degrees(Double(index % 5) * 24 - 48))
                    .position(x: geo.x(0.03 + CGFloat(index) * 0.063),
                              y: geo.under(8 + CGFloat(index % 4) * 15))
            }
        }
    }

    private var shore: some View {
        ZStack {
            SceneryGroundPatch(width: geo.groundWidth, height: geo.groundDepth,
                               crownColor: Color(red: 0.95, green: 0.91, blue: 0.75),
                               earthColor: Color(red: 0.48, green: 0.40, blue: 0.26),
                               rimColor: Color(red: 0.99, green: 0.97, blue: 0.87))
                .position(geo.groundCenter)

            ForEach(0..<5, id: \.self) { index in
                let spot = geo.beside(index.isMultiple(of: 2) ? -1 : 1,
                                      step: CGFloat(index / 2))
                Planted(x: spot.x, footY: spot.y,
                        width: geo.u(32), height: geo.u(18 + CGFloat(index % 3) * 7)) {
                    SceneryTuft(width: geo.u(32), height: geo.u(18 + CGFloat(index % 3) * 7),
                                color: strawDeep, light: straw, blades: 7)
                }
            }

            Planted(x: geo.beside(-1, step: 4).x,
                    footY: geo.beside(-1, step: 4).y,
                    width: geo.u(58), height: geo.u(36)) {
                SceneryHayBale(width: geo.u(58), height: geo.u(36),
                               straw: strawDeep, strawLight: straw)
            }

            LoungerShadow(geo: geo, opacity: 0.19)
        }
    }

    private var props: some View {
        ZStack {
            // The waterhole the enclosure is built around: a concrete lip, then
            // water in the elephant's own blue.
            ZStack {
                Ellipse()
                    .fill(Color(red: 0.78, green: 0.75, blue: 0.68))
                    .frame(width: geo.u(196), height: geo.u(64))
                Ellipse()
                    .fill(LinearGradient(colors: [character.tintColor,
                                                  character.deepColor],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: geo.u(166), height: geo.u(48))
                Capsule()
                    .fill(Color.white.opacity(0.38))
                    .frame(width: geo.u(70), height: geo.u(5))
                    .offset(x: -geo.u(22), y: -geo.u(8))
                Capsule()
                    .fill(Color.white.opacity(0.24))
                    .frame(width: geo.u(44), height: geo.u(4))
                    .offset(x: geo.u(30), y: geo.u(7))
            }
            .position(x: geo.x(0.15), y: geo.under(44))

            SceneryZooSign(width: geo.u(86), height: geo.u(96),
                           board: Color(red: 0.96, green: 0.93, blue: 0.84),
                           post: timberDark,
                           accent: character.color, accentDeep: character.deepColor)
                .frame(width: geo.u(86), height: geo.u(96), alignment: .bottom)
                .position(x: geo.x(0.945), y: geo.under(18) - geo.u(48))

            Capsule()
                .fill(timberDark.opacity(0.85))
                .frame(width: geo.u(96), height: geo.u(18))
                .rotationEffect(.degrees(-5))
                .position(x: geo.x(0.30), y: geo.under(46))

            SceneryHayBale(width: geo.u(48), height: geo.u(30),
                           straw: strawDeep, strawLight: straw)
                .position(x: geo.x(0.80), y: geo.under(38))

            ForEach(0..<4, id: \.self) { index in
                Ellipse()
                    .fill(Color(red: 0.72, green: 0.66, blue: 0.52))
                    .frame(width: geo.u(15 + CGFloat(index) * 4), height: geo.u(8))
                    .position(x: geo.x(0.44 + CGFloat(index) * 0.11),
                              y: geo.under(12 + CGFloat(index % 2) * 10))
            }
        }
    }

    private var motion: some View {
        ZStack {
            SceneryCloud(width: geo.u(94))
                .position(x: -geo.u(70), y: geo.y(0.15))
                .sceneryDrift(dx: geo.size.width + geo.u(200), period: 118)

            ForEach(0..<3, id: \.self) { index in
                SceneryBush(width: geo.u(74), height: geo.u(40),
                            color: jungle, light: jungleLight)
                    .frame(width: geo.u(74), height: geo.u(40), alignment: .bottom)
                    .scenerySway(1.8, period: 5.4 + Double(index), delay: Double(index) * 1.4)
                    .position(x: geo.x(0.16 + CGFloat(index) * 0.34),
                              y: geo.horizon - geo.u(16) - geo.u(20))
            }

            SceneryTuft(width: geo.u(40), height: geo.u(64),
                        color: strawDeep, light: straw, blades: 8)
                .frame(width: geo.u(40), height: geo.u(64), alignment: .bottom)
                .scenerySway(3.4, period: 4.8)
                .position(x: geo.x(0.055), y: geo.under(14) - geo.u(32))

            SceneryButterfly(width: geo.u(22), wing: Color.white,
                             wingDeep: character.color)
                .position(x: -geo.u(30), y: geo.y(0.50))
                .sceneryDrift(dx: geo.size.width + geo.u(70), dy: -geo.u(36), period: 26)

            SkyFlight(geo: geo, count: 3, span: 19, topShare: 0.20,
                      color: jungle.opacity(0.42), period: 24)

            SkyFlight(geo: geo, count: 2, span: 13, topShare: 0.09,
                      color: jungle.opacity(0.26), period: 39, rightwards: false)

            SceneryCloud(width: geo.u(68), opacity: 0.56)
                .position(x: -geo.u(52), y: geo.y(0.30))
                .sceneryDrift(dx: geo.size.width + geo.u(176), period: 158, delay: 22)
        }
    }
}

// MARK: - Bear: the pine forest

private struct ForestScene: View {
    let character: AnimalCharacter
    let geo: SceneGeometry
    let showsMotion: Bool

    private let skyTop = Color(red: 0.70, green: 0.83, blue: 0.90)
    private let skyLow = Color(red: 0.94, green: 0.96, blue: 0.90)
    private let farPine = Color(red: 0.52, green: 0.66, blue: 0.62)
    private let midPine = Color(red: 0.26, green: 0.45, blue: 0.34)
    private let nearPine = Color(red: 0.16, green: 0.33, blue: 0.24)
    private let moss = Color(red: 0.34, green: 0.46, blue: 0.22)
    private let mossLight = Color(red: 0.58, green: 0.70, blue: 0.35)
    private let soil = Color(red: 0.26, green: 0.20, blue: 0.12)
    private let bark = Color(red: 0.40, green: 0.28, blue: 0.17)

    var body: some View {
        ZStack {
            still.drawingGroup()
            if showsMotion { motion }
        }
    }

    private var still: some View {
        ZStack {
            sky
            timberline
            shore
            floor
        }
    }

    private var sky: some View {
        ZStack {
            LinearGradient(colors: [skyTop, skyLow], startPoint: .top, endPoint: .bottom)

            ScenerySun(diameter: geo.u(58),
                       core: Color(red: 1.0, green: 0.98, blue: 0.88).opacity(0.78),
                       halo: character.tintColor)
                .position(x: geo.x(0.70), y: geo.y(0.12))

            // Mountains behind the treeline.
            ForEach(0..<2, id: \.self) { index in
                SceneryTriangleShape(apex: index == 0 ? 0.45 : 0.6)
                    .fill(Color(red: 0.62, green: 0.70, blue: 0.78).opacity(0.7))
                    .frame(width: geo.u(280 - CGFloat(index) * 70),
                           height: geo.u(130 - CGFloat(index) * 34))
                    .position(x: geo.x(0.24 + CGFloat(index) * 0.44),
                              y: geo.horizon - geo.u(96 - CGFloat(index) * 22))
            }
        }
    }

    private var timberline: some View {
        ZStack {
            ForEach(0..<9, id: \.self) { index in
                let width = geo.u(56 + CGFloat(index % 3) * 14)
                let height = geo.u(120 + CGFloat(index % 4) * 26)
                Planted(x: geo.x(-0.02 + CGFloat(index) * 0.128),
                        footY: geo.horizon - geo.u(14), width: width, height: height) {
                    SceneryConifer(width: width, height: height,
                                   foliage: farPine, shade: farPine.opacity(0.82),
                                   trunk: bark.opacity(0.5))
                }
            }

            ForEach(0..<7, id: \.self) { index in
                let width = geo.u(76 + CGFloat(index % 3) * 18)
                let height = geo.u(164 + CGFloat(index % 3) * 34)
                Planted(x: geo.x(0.02 + CGFloat(index) * 0.166),
                        footY: geo.under(6), width: width, height: height) {
                    SceneryConifer(width: width, height: height,
                                   foliage: midPine, shade: nearPine, trunk: bark)
                }
            }

            // Mist settling between the trunks. Two soft bands rather than one
            // solid one, so it fades into the wood instead of banding across it.
            ForEach(0..<2, id: \.self) { index in
                Capsule()
                    .fill(Color.white.opacity(0.20 - Double(index) * 0.06))
                    .frame(width: geo.size.width * (1.1 - CGFloat(index) * 0.25),
                           height: geo.u(38 + CGFloat(index) * 22))
                    .blur(radius: geo.u(20 + CGFloat(index) * 8))
                    .position(x: geo.x(0.42 + CGFloat(index) * 0.2),
                              y: geo.horizon - geo.u(26 - CGFloat(index) * 14))
            }

            Rectangle()
                .fill(LinearGradient(colors: [moss, soil],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: geo.size.width, height: geo.floorHeight)
                .position(x: geo.x(0.5), y: geo.floorCenter)

            // Undergrowth banked against the foot of the trees, and patches of
            // moss catching the light on the floor in front of it.
            ForEach(0..<7, id: \.self) { index in
                let width = geo.u(62 + CGFloat(index % 3) * 24)
                let height = geo.u(34 + CGFloat(index % 3) * 14)
                Planted(x: geo.x(0.02 + CGFloat(index) * 0.165),
                        footY: geo.under(10 + CGFloat(index % 2) * 6),
                        width: width, height: height) {
                    SceneryBush(width: width, height: height,
                                color: nearPine, light: midPine)
                }
            }

            ForEach(0..<5, id: \.self) { index in
                Ellipse()
                    .fill(mossLight.opacity(0.24))
                    .frame(width: geo.u(80 + CGFloat(index % 3) * 34), height: geo.u(20))
                    .blur(radius: geo.u(4))
                    .position(x: geo.x(0.08 + CGFloat(index) * 0.21),
                              y: geo.under(20 + CGFloat(index % 2) * 26))
            }
        }
    }

    private var shore: some View {
        ZStack {
            SceneryGroundPatch(width: geo.groundWidth, height: geo.groundDepth,
                               crownColor: mossLight,
                               earthColor: soil,
                               rimColor: Color(red: 0.66, green: 0.74, blue: 0.40))
                .position(geo.groundCenter)

            ForEach(0..<5, id: \.self) { index in
                let spot = geo.beside(index.isMultiple(of: 2) ? -1 : 1,
                                      step: CGFloat(index / 2))
                Planted(x: spot.x, footY: spot.y,
                        width: geo.u(38), height: geo.u(22 + CGFloat(index % 3) * 8)) {
                    SceneryFern(width: geo.u(38), height: geo.u(22 + CGFloat(index % 3) * 8),
                                color: midPine, light: moss)
                }
            }

            SceneryMushroom(width: geo.u(24),
                            cap: Color(red: 0.82, green: 0.32, blue: 0.24),
                            stem: Color(red: 0.96, green: 0.93, blue: 0.85))
                .position(geo.beside(-1, step: 3))

            SceneryMushroom(width: geo.u(17),
                            cap: character.color,
                            stem: Color(red: 0.96, green: 0.93, blue: 0.85))
                .position(geo.beside(1, step: 3))

            LoungerShadow(geo: geo, opacity: 0.20)
        }
    }

    private var floor: some View {
        ZStack {
            // A fallen trunk along the left of the floor.
            Capsule()
                .fill(LinearGradient(colors: [bark, character.deepColor],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: geo.u(180), height: geo.u(30))
                .overlay(alignment: .leading) {
                    Ellipse()
                        .fill(Color(red: 0.74, green: 0.60, blue: 0.42))
                        .frame(width: geo.u(14), height: geo.u(26))
                }
                .rotationEffect(.degrees(-4))
                .position(x: geo.x(0.14), y: geo.under(46))

            SceneryFern(width: geo.u(96), height: geo.u(64),
                        color: midPine, light: moss)
                .frame(width: geo.u(96), height: geo.u(64), alignment: .bottom)
                .position(x: geo.x(0.06), y: geo.under(16) - geo.u(32))

            SceneryBush(width: geo.u(90), height: geo.u(46),
                        color: nearPine, light: midPine)
                .frame(width: geo.u(90), height: geo.u(46), alignment: .bottom)
                .position(x: geo.x(0.955), y: geo.under(24) - geo.u(23))

            ForEach(0..<4, id: \.self) { index in
                let width = geo.u(30 + CGFloat(index) * 9)
                let height = geo.u(15 + CGFloat(index % 2) * 7)
                Planted(x: geo.x(0.30 + CGFloat(index) * 0.16),
                        footY: geo.under(16 + CGFloat(index % 2) * 14),
                        width: width, height: height) {
                    SceneryRock(width: width, height: height,
                                color: Color(red: 0.48, green: 0.48, blue: 0.44),
                                light: Color(red: 0.70, green: 0.70, blue: 0.64))
                }
            }
        }
    }

    private var motion: some View {
        ZStack {
            SkyFlight(geo: geo, count: 3, span: 18, topShare: 0.13,
                      color: nearPine.opacity(0.40), period: 29)

            SkyFlight(geo: geo, count: 2, span: 12, topShare: 0.06,
                      color: nearPine.opacity(0.24), period: 46, rightwards: false)

            SkyWisp(geo: geo, heightShare: 0.22, lengthShare: 0.48,
                    opacity: 0.30, period: 182, delay: 12)

            ForEach(0..<3, id: \.self) { index in
                SceneryFern(width: geo.u(80), height: geo.u(56),
                            color: midPine, light: moss)
                    .frame(width: geo.u(80), height: geo.u(56), alignment: .bottom)
                    .scenerySway(3.2, period: 5.2 + Double(index) * 0.8,
                                 delay: Double(index) * 1.1)
                    .position(x: geo.x(index == 2 ? 0.90 : 0.10 + CGFloat(index) * 0.09),
                              y: geo.under(20 + CGFloat(index) * 8) - geo.u(28))
            }

            // Fireflies over the floor.
            ForEach(0..<4, id: \.self) { index in
                Circle()
                    .fill(Color(red: 1.0, green: 0.96, blue: 0.62))
                    .frame(width: geo.u(6), height: geo.u(6))
                    .shadow(color: Color(red: 1.0, green: 0.92, blue: 0.50).opacity(0.9),
                            radius: geo.u(6))
                    .sceneryGlow(low: 0.12, period: 2.6 + Double(index) * 0.5,
                                 delay: Double(index) * 0.7)
                    .position(x: geo.x(0.26 + CGFloat(index) * 0.17),
                              y: geo.under(-6 + CGFloat(index % 3) * 20))
            }

            // Needles and leaves coming down through the canopy.
            ForEach(0..<4, id: \.self) { index in
                SceneryLeafShape()
                    .fill(Color(red: 0.72, green: 0.60, blue: 0.32).opacity(0.75))
                    .frame(width: geo.u(16), height: geo.u(7))
                    .sceneryDrift(dx: geo.u(CGFloat(index % 3) * 26 - 24),
                                  dy: geo.size.height + geo.u(28), spin: 220,
                                  period: 16 + Double(index % 3) * 5,
                                  delay: Double(index) * 3.2)
                    .position(x: geo.x(0.18 + CGFloat(index) * 0.22), y: -geo.u(14))
            }

            Capsule()
                .fill(Color.white.opacity(0.26))
                .frame(width: geo.size.width * 0.6, height: geo.u(34))
                .blur(radius: geo.u(16))
                .position(x: -geo.x(0.2), y: geo.horizon - geo.u(26))
                .sceneryDrift(dx: geo.size.width * 1.5, period: 64)
        }
    }
}

// MARK: - Fox: the autumn wood

private struct AutumnScene: View {
    let character: AnimalCharacter
    let geo: SceneGeometry
    let showsMotion: Bool

    // The wood is warm from the ground up but the sky above it is cool, which
    // is what keeps an autumn scene from collapsing into one sheet of orange.
    private let skyTop = Color(red: 0.66, green: 0.80, blue: 0.90)
    private let skyLow = Color(red: 1.0, green: 0.90, blue: 0.72)
    private let amber = Color(red: 0.93, green: 0.55, blue: 0.17)
    private let ochre = Color(red: 0.84, green: 0.68, blue: 0.22)
    private let rust = Color(red: 0.66, green: 0.28, blue: 0.11)
    private let litter = Color(red: 0.86, green: 0.66, blue: 0.38)
    private let litterDeep = Color(red: 0.50, green: 0.34, blue: 0.16)
    private let bark = Color(red: 0.44, green: 0.32, blue: 0.20)
    private let birch = Color(red: 0.95, green: 0.94, blue: 0.90)

    var body: some View {
        ZStack {
            still.drawingGroup()
            if showsMotion { motion }
        }
    }

    private var still: some View {
        ZStack {
            sky
            wood
            shore
            floor
        }
    }

    private var sky: some View {
        ZStack {
            LinearGradient(colors: [skyTop, skyLow], startPoint: .top, endPoint: .bottom)

            ScenerySun(diameter: geo.u(88),
                       core: Color(red: 1.0, green: 0.90, blue: 0.56).opacity(0.86),
                       halo: character.color)
                .position(x: geo.x(0.23), y: geo.y(0.16))

            Ellipse()
                .fill(character.tintColor.opacity(0.62))
                .frame(width: geo.x(0.94), height: geo.u(94))
                .position(x: geo.x(0.68), y: geo.horizon - geo.u(50))
        }
    }

    private var wood: some View {
        ZStack {
            ForEach(0..<6, id: \.self) { index in
                let width = geo.u(110 + CGFloat(index % 3) * 28)
                let height = geo.u(140 + CGFloat(index % 3) * 34)
                Planted(x: geo.x(0.02 + CGFloat(index) * 0.195),
                        footY: geo.horizon - geo.u(14), width: width, height: height) {
                    SceneryCanopyTree(width: width, height: height,
                                      crown: index.isMultiple(of: 2) ? amber : ochre,
                                      crownLight: character.tintColor,
                                      trunk: bark)
                        .opacity(0.78)
                }
            }

            // Birch trunks nearer the eye, cut off by the top of the frame.
            ForEach(0..<3, id: \.self) { index in
                birchTrunk(index: index)
            }

            ForEach(0..<6, id: \.self) { index in
                let width = geo.u(90 + CGFloat(index % 3) * 26)
                let height = geo.u(44 + CGFloat(index % 3) * 12)
                Planted(x: geo.x(0.04 + CGFloat(index) * 0.20),
                        footY: geo.under(4), width: width, height: height) {
                    SceneryBush(width: width, height: height,
                                color: rust, light: amber)
                        .opacity(0.85)
                }
            }

            Rectangle()
                .fill(LinearGradient(colors: [litter, litterDeep],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: geo.size.width, height: geo.floorHeight)
                .position(x: geo.x(0.5), y: geo.floorCenter)
        }
    }

    private func birchTrunk(index: Int) -> some View {
        let width = geo.u(20 - CGFloat(index) * 3)
        let height = geo.horizon - geo.u(10)
        return ZStack {
            Capsule()
                .fill(LinearGradient(colors: [birch, Color(red: 0.82, green: 0.80, blue: 0.75)],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(width: width, height: height)
            ForEach(0..<4, id: \.self) { mark in
                Capsule()
                    .fill(bark.opacity(0.55))
                    .frame(width: width * 0.5, height: geo.u(5))
                    .offset(x: mark.isMultiple(of: 2) ? -width * 0.14 : width * 0.16,
                            y: height * (CGFloat(mark) * 0.21 - 0.30))
            }
        }
        .frame(width: width, height: height)
        .position(x: geo.x(index == 2 ? 0.885 : 0.05 + CGFloat(index) * 0.11),
                  y: height * 0.5)
    }

    private var shore: some View {
        ZStack {
            SceneryGroundPatch(width: geo.groundWidth, height: geo.groundDepth,
                               crownColor: Color(red: 0.92, green: 0.76, blue: 0.46),
                               earthColor: Color(red: 0.48, green: 0.33, blue: 0.17),
                               rimColor: Color(red: 0.98, green: 0.88, blue: 0.62))
                .position(geo.groundCenter)

            ForEach(0..<6, id: \.self) { index in
                let spot = geo.beside(index.isMultiple(of: 2) ? -1 : 1,
                                      step: CGFloat(index / 2))
                Planted(x: spot.x, footY: spot.y,
                        width: geo.u(34), height: geo.u(20 + CGFloat(index % 3) * 8)) {
                    SceneryTuft(width: geo.u(34), height: geo.u(20 + CGFloat(index % 3) * 8),
                                color: litterDeep, light: ochre, blades: 7)
                }
            }

            // Fallen leaves banked up against the sides of the mound.
            ForEach(0..<7, id: \.self) { index in
                let side: CGFloat = index.isMultiple(of: 2) ? -1 : 1
                SceneryLeafShape()
                    .fill(index.isMultiple(of: 3) ? amber : rust)
                    .frame(width: geo.u(20), height: geo.u(9))
                    .rotationEffect(.degrees(Double(index) * 37 - 60))
                    .position(geo.beside(side, step: 2.2 + CGFloat(index) * 0.28))
            }
        }
    }

    private var floor: some View {
        ZStack {
            Capsule()
                .fill(LinearGradient(colors: [bark, Color(red: 0.32, green: 0.22, blue: 0.13)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: geo.u(160), height: geo.u(28))
                .overlay(alignment: .trailing) {
                    Ellipse()
                        .fill(Color(red: 0.80, green: 0.66, blue: 0.46))
                        .frame(width: geo.u(13), height: geo.u(24))
                }
                .rotationEffect(.degrees(5))
                .position(x: geo.x(0.86), y: geo.under(44))

            SceneryMushroom(width: geo.u(26), cap: rust,
                            stem: Color(red: 0.97, green: 0.94, blue: 0.86))
                .position(x: geo.x(0.20), y: geo.under(28))

            SceneryMushroom(width: geo.u(18), cap: amber,
                            stem: Color(red: 0.97, green: 0.94, blue: 0.86))
                .position(x: geo.x(0.26), y: geo.under(20))

            ForEach(0..<9, id: \.self) { index in
                SceneryLeafShape()
                    .fill(index.isMultiple(of: 3)
                          ? ochre : (index.isMultiple(of: 2) ? amber : rust))
                    .frame(width: geo.u(22), height: geo.u(10))
                    .rotationEffect(.degrees(Double(index) * 41 - 90))
                    .position(x: geo.x(0.06 + CGFloat(index) * 0.105),
                              y: geo.under(6 + CGFloat(index % 4) * 13))
            }

            LoungerShadow(geo: geo, opacity: 0.18)
        }
    }

    private var motion: some View {
        ZStack {
            SceneryTuft(width: geo.u(48), height: geo.u(84),
                        color: litterDeep, light: ochre, blades: 8)
                .frame(width: geo.u(48), height: geo.u(84), alignment: .bottom)
                .scenerySway(3.6, period: 4.8)
                .position(x: geo.x(0.045), y: geo.under(20) - geo.u(42))

            SceneryTuft(width: geo.u(42), height: geo.u(72),
                        color: litterDeep, light: ochre, blades: 7)
                .frame(width: geo.u(42), height: geo.u(72), alignment: .bottom)
                .scenerySway(4.2, period: 5.6, delay: 1.4)
                .position(x: geo.x(0.955), y: geo.under(14) - geo.u(36))

            // The wood shedding, which is the whole point of the season.
            ForEach(0..<6, id: \.self) { index in
                SceneryLeafShape()
                    .fill(index.isMultiple(of: 3)
                          ? ochre : (index.isMultiple(of: 2) ? amber : rust))
                    .frame(width: geo.u(20 + CGFloat(index % 3) * 5),
                           height: geo.u(9 + CGFloat(index % 3) * 2))
                    .sceneryDrift(dx: geo.u(CGFloat(index % 4) * 34 - 50),
                                  dy: geo.size.height + geo.u(30), spin: 320,
                                  period: 14 + Double(index % 4) * 4,
                                  delay: Double(index) * 2.3)
                    .position(x: geo.x(0.12 + CGFloat(index) * 0.15), y: -geo.u(16))
            }

            SkyFlight(geo: geo, count: 4, span: 19, topShare: 0.14,
                      color: bark.opacity(0.42), period: 25)

            SkyFlight(geo: geo, count: 2, span: 13, topShare: 0.07,
                      color: bark.opacity(0.26), period: 41, rightwards: false)

            // The wood has no cloud cover of its own, so the sky above it was
            // the one part of the scene that never changed.
            SceneryCloud(width: geo.u(82), opacity: 0.58)
                .position(x: -geo.u(64), y: geo.y(0.12))
                .sceneryDrift(dx: geo.size.width + geo.u(190), period: 124)

            SceneryCloud(width: geo.u(58), opacity: 0.46)
                .position(x: -geo.u(46), y: geo.y(0.26))
                .sceneryDrift(dx: geo.size.width + geo.u(150), period: 166, delay: 24)
        }
    }
}
