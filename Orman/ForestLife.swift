import SwiftUI
import SceneKit
import AVFoundation
import UIKit

@MainActor
final class ForestSound: ObservableObject {
    @Published private(set) var enabled = false
    @Published var error: String?
    private var layers: [String: AVAudioPlayer] = [:]
    private weak var view: SCNView?
    private var sources: [SCNAudioSource] = []
    private var deerCall: AVAudioPlayer?
    private var lastDeerCall = -Double.infinity
    private var rabbitCall: SCNAudioSource?
    private var lastRabbitCall = -Double.infinity

    func playDeerCall(at animal: SCNNode) {
        guard enabled, active, !interrupted, running,
              ProcessInfo.processInfo.systemUptime - lastDeerCall >= 0.9 else { return }
        do {
            if deerCall == nil {
                guard let url = Bundle.main.url(forResource: "ForestDeer", withExtension: "wav") else { throw CocoaError(.fileNoSuchFile) }
                let player = try AVAudioPlayer(contentsOf: url)
                player.numberOfLoops = 0
                player.volume = 0.45
                player.prepareToPlay()
                deerCall = player
            }
            guard let player = deerCall else { return }
            // A deliberate tap needs audible feedback even with the forest zoomed out.
            // Preserve left/right placement without SceneKit's distance attenuation.
            if let camera = view?.pointOfView?.presentation {
                let local = camera.convertPosition(animal.presentation.worldPosition, from: nil)
                let distance = max(0.001, hypot(Double(local.x), Double(local.z)))
                player.pan = Float(max(-0.65, min(0.65, Double(local.x)/distance * 0.65)))
            } else { player.pan = 0 }
            player.currentTime = 0
            guard player.play() else { throw CocoaError(.fileReadUnknown) }
            lastDeerCall = ProcessInfo.processInfo.systemUptime
        } catch {
            deerCall = nil
            self.error = T("Ceylan sesi çalınamadı. Yeniden deneyebilirsin.", "Couldn't play the deer call. You can try again.", "Der Hirschruf konnte nicht abgespielt werden. Du kannst es erneut versuchen.")
        }
    }

    // Rabbits only ever call out when touched, so this only fires from a tap.
    func playRabbitCall(at animal: SCNNode) {
        guard enabled, active, !interrupted, running,
              ProcessInfo.processInfo.systemUptime - lastRabbitCall >= 1.0 else { return }
        if rabbitCall == nil, let url = Bundle.main.url(forResource: "ForestRabbit", withExtension: "wav") {
            let source = SCNAudioSource(url: url)
            source?.isPositional = true; source?.loops = false; source?.volume = 0.28
            source?.load(); rabbitCall = source
        }
        guard let rabbitCall else { return }
        lastRabbitCall = ProcessInfo.processInfo.systemUptime
        animal.removeAllAudioPlayers()
        animal.addAudioPlayer(SCNAudioPlayer(source: rabbitCall))
    }
    private var active = true
    private var interrupted = false
    private var night = false
    private var radius = 14.0
    private var running = false
    private var observers: [NSObjectProtocol] = []

    init() {
        observers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) ?? 0
            let options = (note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt) ?? 0
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.interrupted = type == AVAudioSession.InterruptionType.began.rawValue
                if !self.interrupted && !AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume) { self.enabled = false }
                self.update()
            }
        })
        observers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt) ?? 0
            if reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue {
                Task { @MainActor [weak self] in self?.setEnabled(false) }
            }
        })
    }
    deinit { for observer in observers { NotificationCenter.default.removeObserver(observer) } }
    func setEnabled(_ value: Bool) { enabled = value; update() }
    func setActive(_ value: Bool) { active = value; update() }

    func configure(view: SCNView, night: Bool, radius: Double) {
        let changed = self.view !== view || self.night != night || self.radius != radius
        if self.view !== view { stop() }
        self.view = view; self.night = night; self.radius = radius
        guard changed else { return }
        if let water = view.scene?.rootNode.childNode(withName: "forestAudio", recursively: false) { positionWater(water) }
        update()
    }

    private func positionWater(_ water: SCNNode) {
        for (index, node) in water.childNodes.enumerated() {
            let z = Double(index - 1) * radius * 0.45
            node.position = SCNVector3(ForestTerrain.riverX(z), 0.15, z)
        }
    }

    private func stop() {
        layers.values.forEach { $0.pause() }
        deerCall?.stop()
        deerCall?.currentTime = 0
        view?.scene?.rootNode.childNode(withName: "forestAnimals", recursively: false)?.childNodes.forEach { $0.removeAllAudioPlayers() }
        if running {
            if let water = view?.scene?.rootNode.childNode(withName: "forestAudio", recursively: false) {
                water.childNodes.forEach { $0.removeAllAudioPlayers() }
                water.removeFromParentNode()
            }
            view?.audioEngine.pause()
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        running = false
    }

    private func update() {
        guard enabled, active, !interrupted, let view else { stop(); return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, mode: .default, options: .mixWithOthers)
            try session.setActive(true)
            running = true
            for name in ["Wind", "Birds"] where layers[name] == nil {
                guard let url = Bundle.main.url(forResource: "Forest" + name, withExtension: "wav") else { throw CocoaError(.fileNoSuchFile) }
                let player = try AVAudioPlayer(contentsOf: url)
                player.numberOfLoops = -1; player.volume = 0; player.prepareToPlay()
                layers[name] = player
            }
            if sources.isEmpty {
                guard let url = Bundle.main.url(forResource: "ForestRiver", withExtension: "wav") else { throw CocoaError(.fileNoSuchFile) }
                var loadedSources: [SCNAudioSource] = []
                for index in 0..<3 {
                    guard let source = SCNAudioSource(url: url) else { throw CocoaError(.fileReadCorruptFile) }
                    source.isPositional = true; source.loops = true; source.volume = 0.22
                    source.rate = 0.94 + Float(index) * 0.06
                    source.load(); loadedSources.append(source)
                }
                sources = loadedSources
            }
            // SceneKit follows the active camera as its listener when this is nil.
            view.audioListener = nil
            let attenuation = view.audioEnvironmentNode.distanceAttenuationParameters
            attenuation.distanceAttenuationModel = .inverse
            attenuation.referenceDistance = 7
            attenuation.maximumDistance = 180
            attenuation.rolloffFactor = 1.25
            if view.scene?.rootNode.childNode(withName: "forestAudio", recursively: false) == nil {
                let water = SCNNode(); water.name = "forestAudio"
                for index in 0..<3 {
                    let node = SCNNode(); node.name = "riverSound\(index)"
                    water.addChildNode(node)
                }
                positionWater(water)
                view.scene?.rootNode.addChildNode(water)
                for (index, node) in water.childNodes.enumerated() { node.addAudioPlayer(SCNAudioPlayer(source: sources[index])) }
            }
            running = true
            if !view.audioEngine.isRunning { try view.audioEngine.start() }
            for (name, player) in layers {
                if !player.isPlaying { guard player.play() else { throw CocoaError(.fileReadUnknown) } }
                // Keep nights quiet: wind and the positional river, without periodic synthetic chirps.
                let volume: Float = name == "Wind" ? 0.16 : (night ? 0 : 0.20)
                player.setVolume(volume, fadeDuration: 2.5)
            }
        } catch {
            enabled = false
            stop()
            self.error = T("Doğa sesleri açılamadı. Yeniden deneyebilirsin.", "Couldn't turn on nature sounds. You can try again.", "Naturgeräusche konnten nicht aktiviert werden. Du kannst es erneut versuchen.")
        }
    }
}

enum ForestLife {
    static func update(_ scene: SCNScene?, active: Bool, reduceMotion: Bool, night: Bool, weather: ForestWeather?) {
        guard let root = scene?.rootNode else { return }
        let moving = active && !reduceMotion
        let plants = root.childNode(withName: "plants", recursively: false)?.childNodes ?? []
        for (index, plant) in plants.enumerated() {
            guard let canopy = plant.childNode(withName: "canopy", recursively: true) else { continue }
            if moving && index < 100 {
                if canopy.action(forKey: "breeze") == nil {
                    let duration = 2.4 + Double(index % 5) * 0.25
                    let left = SCNAction.rotateTo(x: 0, y: 0, z: -0.022, duration: duration)
                    let right = SCNAction.rotateTo(x: 0, y: 0, z: 0.022, duration: duration)
                    left.timingMode = .easeInEaseOut
                    right.timingMode = .easeInEaseOut
                    canopy.runAction(.repeatForever(.sequence([left, right])), forKey: "breeze")
                }
            } else {
                canopy.removeAction(forKey: "breeze")
                canopy.eulerAngles = SCNVector3Zero
            }
        }
        let life: SCNNode
        if let existing = root.childNode(withName: "forestLife", recursively: false) { life = existing }
        else {
            life = SCNNode()
            life.name = "forestLife"
            for index in 0..<9 { life.addChildNode(butterfly(index)) }
            root.addChildNode(life)
        }
        let fairWeather = weather == nil || weather == .clear || weather == .cloudy
        life.isHidden = night || !fairWeather
        // The lamp post's topper morphs between a glowing lantern at night
        // and a quiet birdhouse during the day.
        if let lampPost = root.childNode(withName: "lampPost", recursively: false) {
            lampPost.childNode(withName: "lanternTop", recursively: false)?.isHidden = !night
            lampPost.childNode(withName: "birdhouseTop", recursively: false)?.isHidden = night
        }
        for butterfly in life.childNodes {
            if moving && !life.isHidden {
                if butterfly.action(forKey: "flight") == nil {
                    let flight = ButterflyFlight()
                    let action = SCNAction.customAction(duration: 600) { [weak root] node, elapsed in
                        let radius = Double(root?.childNode(withName: "ground", recursively: false)?.scale.x ?? 1) * 14
                        flight.advance(node, elapsed: Double(elapsed), radius: radius)
                    }
                    butterfly.runAction(.repeatForever(action), forKey: "flight")
                }
            } else {
                butterfly.removeAction(forKey: "flight")
                butterfly.eulerAngles = SCNVector3Zero
                for wing in butterfly.childNodes where wing.name == "leftWing" || wing.name == "rightWing" {
                    wing.eulerAngles.z = 0
                }
            }
        }
        let birds: SCNNode
        if let existing = root.childNode(withName: "forestBirds", recursively: false) { birds = existing }
        else {
            birds = SCNNode()
            birds.name = "forestBirds"
            for index in 0..<2 { birds.addChildNode(bird(index)) }
            root.addChildNode(birds)
        }
        birds.isHidden = night || !fairWeather
        for bird in birds.childNodes {
            if moving && !birds.isHidden {
                if bird.action(forKey: "birdFlight") == nil {
                    let flight = BirdFlight()
                    let action = SCNAction.customAction(duration: 600) { [weak root] node, elapsed in
                        let radius = Double(root?.childNode(withName: "ground", recursively: false)?.scale.x ?? 1) * 14
                        flight.advance(node, elapsed: Double(elapsed), radius: radius)
                    }
                    bird.runAction(.repeatForever(action), forKey: "birdFlight")
                }
            } else {
                bird.removeAction(forKey: "birdFlight")
                bird.eulerAngles = SCNVector3Zero
                for wing in bird.childNodes where wing.name == "leftBirdWing" || wing.name == "rightBirdWing" {
                    wing.eulerAngles.z = 0
                }
            }
        }
        updateDeer(root, moving: moving)
        updateRabbits(root, moving: moving)
    }

    final class ButterflyFlight {
        private var points: [SCNVector3] = []
        private var previousTime = 0.0
        private var progress = 0.0
        private var duration = 8.0
        private var direction = Double.random(in: 0..<(2 * .pi))
        private let phase = Double.random(in: 0..<(2 * .pi))
        private let flutterRate = Double.random(in: 8...11)
        private var wingPhase = 0.0

        func advance(_ node: SCNNode, elapsed: Double, radius: Double) {
            let dt = max(0, min(0.1, elapsed >= previousTime ? elapsed - previousTime : elapsed))
            previousTime = elapsed
            let limit = max(2, radius - 1)
            func bounded(_ point: SCNVector3) -> SCNVector3 {
                let distance = hypot(Double(point.x), Double(point.z))
                let factor = distance > limit ? limit / distance : 1
                return SCNVector3(Double(point.x) * factor, max(0.9, min(5.5, Double(point.y))), Double(point.z) * factor)
            }
            if points.contains(where: { hypot(Double($0.x), Double($0.z)) > limit + 0.001 }) {
                points.removeAll()
                node.position = bounded(node.position)
            }
            if points.isEmpty || progress >= duration {
                let start = bounded(node.position)
                let angle = Double.random(in: 0..<(2 * .pi))
                let distance = Double.random(in: 3...9)
                let destination = bounded(SCNVector3(Double(start.x) + cos(angle) * distance, Double.random(in: 0.9...5.5), Double(start.z) + sin(angle) * distance))
                let nextDirection = angle + Double.random(in: -0.9...0.9)
                let first = bounded(SCNVector3(Double(start.x) + cos(direction) * 1.4, Double(start.y), Double(start.z) + sin(direction) * 1.4))
                let second = bounded(SCNVector3(Double(destination.x) - cos(nextDirection) * 1.4, Double(destination.y), Double(destination.z) - sin(nextDirection) * 1.4))
                points = [start, first, second, destination]
                direction = nextDirection
                progress = 0
                duration = Double.random(in: 7...12)
            }
            // Real butterflies flutter in bursts and glide, rather than
            // cruising at a bee-like constant speed.
            let burst = max(0, sin(elapsed * 1.6 + phase))
            progress = min(duration, progress + dt * (0.45 + burst))
            let t = progress / duration, u = 1 - t
            let weights = [u*u*u, 3*u*u*t, 3*u*t*t, t*t*t]
            var x = 0.0, y = 0.0, z = 0.0
            for index in 0..<4 {
                x += Double(points[index].x) * weights[index]
                y += Double(points[index].y) * weights[index]
                z += Double(points[index].z) * weights[index]
            }
            // An erratic wobble layered on the smooth path, since a butterfly
            // never glides in a straight line the way a bird or bee does.
            x += sin(elapsed * 3.1 + phase) * 0.16 + sin(elapsed * 5.3 + phase * 1.7) * 0.06
            y += sin(elapsed * 4.2 + phase * 0.6) * 0.09
            z += cos(elapsed * 2.7 + phase) * 0.16
            let dx = x - Double(node.position.x), dz = z - Double(node.position.z)
            if hypot(dx, dz) > 0.0001 {
                let heading = atan2(-dx, -dz)
                let turn = atan2(sin(heading - Double(node.eulerAngles.y)), cos(heading - Double(node.eulerAngles.y)))
                node.eulerAngles.y += Float(turn * min(1, dt * 4))
            }
            node.position = SCNVector3(x, y, z)
            // Bank into turns and tumble slightly, instead of flying dead level.
            node.eulerAngles.z = Float(sin(wingPhase) * 0.12 + sin(elapsed * 1.3 + phase) * 0.1)
            node.eulerAngles.x = Float(sin(elapsed * 2.2 + phase) * 0.08)
            // Wingbeat speed tracks the current flutter burst; faster flaps
            // during a push, slower ones while gliding.
            wingPhase += dt * flutterRate * (0.6 + burst)
            let flap = Float(sin(wingPhase))
            let amount = flap >= 0 ? flap * 0.85 : flap * 0.15
            for wing in node.childNodes where wing.name == "leftWing" || wing.name == "rightWing" {
                let sign: Float = wing.name == "leftWing" ? 1 : -1
                wing.eulerAngles.z = sign * amount
            }
        }
    }

    // A bird's flight reuses the same Bézier-hop shape as a butterfly's, but
    // glides higher, straighter and with far less wobble, and flaps evenly
    // on both strokes instead of the butterfly's asymmetric flutter.
    final class BirdFlight {
        private var points: [SCNVector3] = []
        private var previousTime = 0.0
        private var progress = 0.0
        private var duration = 10.0
        private var direction = Double.random(in: 0..<(2 * .pi))
        private let phase = Double.random(in: 0..<(2 * .pi))
        private let flapRate = Double.random(in: 4.3...5.7)
        private var wingPhase = 0.0

        func advance(_ node: SCNNode, elapsed: Double, radius: Double) {
            let dt = max(0, min(0.1, elapsed >= previousTime ? elapsed - previousTime : elapsed))
            previousTime = elapsed
            let limit = max(3, radius - 1)
            func bounded(_ point: SCNVector3) -> SCNVector3 {
                let distance = hypot(Double(point.x), Double(point.z))
                let factor = distance > limit ? limit / distance : 1
                return SCNVector3(Double(point.x) * factor, max(3.2, min(8.5, Double(point.y))), Double(point.z) * factor)
            }
            if points.contains(where: { hypot(Double($0.x), Double($0.z)) > limit + 0.001 }) {
                points.removeAll()
                node.position = bounded(node.position)
            }
            if points.isEmpty || progress >= duration {
                let start = bounded(node.position)
                let angle = Double.random(in: 0..<(2 * .pi))
                let distance = Double.random(in: 5...12)
                let destination = bounded(SCNVector3(Double(start.x) + cos(angle) * distance, Double.random(in: 3.2...8.5), Double(start.z) + sin(angle) * distance))
                let nextDirection = angle + Double.random(in: -0.5...0.5)
                let first = bounded(SCNVector3(Double(start.x) + cos(direction) * 2.5, Double(start.y), Double(start.z) + sin(direction) * 2.5))
                let second = bounded(SCNVector3(Double(destination.x) - cos(nextDirection) * 2.5, Double(destination.y), Double(destination.z) - sin(nextDirection) * 2.5))
                points = [start, first, second, destination]
                direction = nextDirection
                progress = 0
                duration = Double.random(in: 9...14)
            }
            progress = min(duration, progress + dt)
            let t = progress / duration, u = 1 - t
            let weights = [u*u*u, 3*u*u*t, 3*u*t*t, t*t*t]
            var x = 0.0, y = 0.0, z = 0.0
            for index in 0..<4 {
                x += Double(points[index].x) * weights[index]
                y += Double(points[index].y) * weights[index]
                z += Double(points[index].z) * weights[index]
            }
            // A gentle bob rides on top of the smooth glide path.
            y += sin(elapsed * 2.0 + phase) * 0.05
            let dx = x - Double(node.position.x), dz = z - Double(node.position.z)
            if hypot(dx, dz) > 0.0001 {
                let heading = atan2(-dx, -dz)
                let turn = atan2(sin(heading - Double(node.eulerAngles.y)), cos(heading - Double(node.eulerAngles.y)))
                node.eulerAngles.y += Float(turn * min(1, dt * 3))
            }
            node.position = SCNVector3(x, y, z)
            node.eulerAngles.z = Float(sin(elapsed * 0.8 + phase) * 0.08)
            wingPhase += dt * flapRate
            let flap = Float(sin(wingPhase)) * 0.7
            for wing in node.childNodes where wing.name == "leftBirdWing" || wing.name == "rightBirdWing" {
                let sign: Float = wing.name == "leftBirdWing" ? 1 : -1
                wing.eulerAngles.z = sign * flap
            }
        }
    }

    static func reactToTouch(_ animal: SCNNode, cameraPosition: SCNVector3, sceneRoot: SCNNode) {
        guard animal.action(forKey: "stroll") != nil,
              animal.action(forKey: "touchReaction") == nil else { return }
        let local = animal.convertPosition(cameraPosition, from: nil)
        let yaw = max(-1.15, min(1.15, atan2(-Double(local.x), -Double(local.z))))
        animal.childNode(withName: "touchRetreat", recursively: false)?.removeFromParentNode()
        if Int.random(in: 0..<3) == 0 {
            let radius = Double(sceneRoot.childNode(withName: "ground", recursively: false)?.scale.x ?? 1) * 14
            let obstacles = (sceneRoot.childNode(withName: "plants", recursively: false)?.childNodes.map { $0.position } ?? []) + WaterMillAsset.obstacles(in: sceneRoot) + ForestSwingAsset.obstacles(in: sceneRoot)
            if let destination = retreatDestination(from: animal.position, camera: cameraPosition, radius: radius, obstacles: obstacles) {
                // This marker stores a world-space destination for the existing navigator.
                let marker = SCNNode(); marker.name = "touchRetreat"; marker.position = destination
                animal.addChildNode(marker)
            }
        }
        animal.runAction(.sequence([
            .customAction(duration: 2.2) { node, elapsed in
                touchPose(node, elapsed: Double(elapsed), yaw: yaw)
            },
            .run { node in touchPose(node, elapsed: 2.2, yaw: 0) }
        ]), forKey: "touchReaction")
    }

    static func touchPose(_ animal: SCNNode, elapsed: Double, yaw: Double) {
        let weight = max(0, min(1, min(elapsed / 0.35, (2.2 - elapsed) / 0.45)))
        let smooth = weight * weight * (3 - 2 * weight)
        animal.childNode(withName: "neck", recursively: true)?.eulerAngles.y = Float(yaw * smooth)
        for (name, base, phase) in [("earLeft", 0.65, 0.0), ("earRight", -0.65, 0.7)] {
            animal.childNode(withName: name, recursively: true)?.eulerAngles.z = Float(base + sin(elapsed * 15 + phase) * 0.22 * smooth)
        }
    }

    // Unlike deer, a touched rabbit always bolts rather than sometimes just glancing over.
    static func reactToRabbitTouch(_ animal: SCNNode, cameraPosition: SCNVector3, sceneRoot: SCNNode) {
        guard animal.action(forKey: "rabbitWander") != nil,
              animal.action(forKey: "touchReaction") == nil else { return }
        animal.childNode(withName: "touchRetreat", recursively: false)?.removeFromParentNode()
        let radius = Double(sceneRoot.childNode(withName: "ground", recursively: false)?.scale.x ?? 1) * 14
        let obstacles = (sceneRoot.childNode(withName: "plants", recursively: false)?.childNodes.map { $0.position } ?? []) + WaterMillAsset.obstacles(in: sceneRoot) + ForestSwingAsset.obstacles(in: sceneRoot)
        if let destination = retreatDestination(from: animal.position, camera: cameraPosition, radius: radius, obstacles: obstacles) {
            // This marker stores a world-space destination for the existing navigator.
            let marker = SCNNode(); marker.name = "touchRetreat"; marker.position = destination
            animal.addChildNode(marker)
        }
        animal.runAction(.sequence([
            .customAction(duration: 0.3) { node, elapsed in rabbitStartlePose(node, elapsed: Double(elapsed)) },
            .run { node in rabbitStartlePose(node, elapsed: 0.3) }
        ]), forKey: "touchReaction")
    }

    static func rabbitStartlePose(_ animal: SCNNode, elapsed: Double) {
        let weight = max(0, min(1, min(elapsed / 0.08, (0.3 - elapsed) / 0.15)))
        let smooth = weight * weight * (3 - 2 * weight)
        for name in ["earLeft", "earRight"] {
            animal.childNode(withName: name, recursively: true)?.eulerAngles.x = Float(-0.9 * smooth)
        }
    }

    static func retreatDestination(from start: SCNVector3, camera: SCNVector3, radius: Double, obstacles: [SCNVector3]) -> SCNVector3? {
        let heading = atan2(Double(start.z-camera.z), Double(start.x-camera.x))
        for distance in [1.8, 1.2, 0.7] {
            for offset in [0.0, 0.4, -0.4, 0.8, -0.8] {
                let point = SCNVector3(Double(start.x)+cos(heading+offset)*distance, 0.03, Double(start.z)+sin(heading+offset)*distance)
                if hypot(Double(point.x), Double(point.z)) <= radius-1.2,
                   DeerWander.clearPath(from: start, to: point, obstacles: obstacles) { return point }
            }
        }
        return nil
    }

    /// Nudges `node` directly away from any position in `others` it's
    /// currently closer to than `minDistance`, so two animals never
    /// visually settle on the same spot. A plain position correction
    /// applied after each wander step — it never touches the pathfinding
    /// or gait logic, so it can't fight either one.
    private static func separate(_ node: SCNNode, from others: [SCNVector3], minDistance: Double) {
        for other in others {
            let dx = Double(node.position.x - other.x)
            let dz = Double(node.position.z - other.z)
            let distance = hypot(dx, dz)
            guard distance > 0.0001, distance < minDistance else { continue }
            let push = (minDistance - distance) * 0.5
            let nx = dx / distance, nz = dz / distance
            node.position.x += Float(nx * push)
            node.position.z += Float(nz * push)
        }
    }

    private static func updateDeer(_ sceneRoot: SCNNode, moving: Bool) {
        let animals: SCNNode
        if let existing = sceneRoot.childNode(withName: "forestAnimals", recursively: false) { animals = existing }
        else {
            animals = SCNNode()
            animals.name = "forestAnimals"
            let radius = Double(sceneRoot.childNode(withName: "ground", recursively: false)?.scale.x ?? 1) * 14
            for index in 0..<2 {
                let animal = deer(index)
                let angle = 0.8 + Double(index) * 2.1
                animal.position = SCNVector3(cos(angle) * (radius - 1.3), 0.03, sin(angle) * (radius - 1.3))
                animals.addChildNode(animal)
                DeerGait().update(animal, dt: 0.016, grazing: 0)
            }
            sceneRoot.addChildNode(animals)
        }
        for animal in animals.childNodes {
            if moving {
                if animal.action(forKey: "stroll") == nil {
                    // Each animal owns independent destinations and timing, with no repeating route.
                    let wander = DeerWander()
                    let action = SCNAction.customAction(duration: 600) { [weak sceneRoot] node, elapsed in
                        guard let sceneRoot else { return }
                        let radius = Double(sceneRoot.childNode(withName: "ground", recursively: false)?.scale.x ?? 1) * 14
                        let obstacles = (sceneRoot.childNode(withName: "plants", recursively: false)?.childNodes.map { $0.position } ?? []) + WaterMillAsset.obstacles(in: sceneRoot) + ForestSwingAsset.obstacles(in: sceneRoot)
                        wander.advance(node, elapsed: Double(elapsed), radius: radius, obstacles: obstacles)
                        // Keep this deer from visually settling on top of the
                        // other deer or a rabbit; a plain position nudge, so
                        // it can't fight the wander/gait logic above.
                        let otherDeer = sceneRoot.childNode(withName: "forestAnimals", recursively: false)?.childNodes.compactMap { $0 !== node ? $0.position : nil } ?? []
                        separate(node, from: otherDeer, minDistance: 0.9)
                        let rabbits = sceneRoot.childNode(withName: "forestRabbits", recursively: false)?.childNodes.map { $0.position } ?? []
                        separate(node, from: rabbits, minDistance: 0.65)
                    }
                    animal.runAction(.repeatForever(action), forKey: "stroll")
                }
            } else {
                animal.removeAction(forKey: "stroll")
                animal.removeAction(forKey: "touchReaction")
                animal.childNode(withName: "touchRetreat", recursively: false)?.removeFromParentNode()
                touchPose(animal, elapsed: 2.2, yaw: 0)
                animal.childNode(withName: "neck", recursively: true)?.eulerAngles.x = 0
                animal.childNode(withName: "neck", recursively: true)?.position.y = 0.66
                animal.childNode(withName: "neck", recursively: true)?.position.z = -0.30
                for legIndex in 0..<4 {
                    let leg = animal.childNode(withName: "leg\(legIndex)", recursively: false)
                    leg?.eulerAngles.x = 0
                    leg?.childNode(withName: "knee", recursively: false)?.eulerAngles.x = 0
                }
            }
        }
    }

    /// World-space planted feet and two-bone inverse kinematics keep the
    /// stance leg still while the body advances. Only the swing foot lifts.
    final class DeerGait {
        private var feet: [SCNVector3] = []
        private var swingIndex: Int?
        private var swingStart = SCNVector3Zero
        private var swingEnd = SCNVector3Zero
        private var swingTime = 0.0
        private var timer = 0.0
        private var nextLeg = 0
        private var previousPosition: SCNVector3?
        private var previousYaw = 0.0
        private var phase = 0.0
        private var blend = 0.0
        private let order = [2, 0, 3, 1]

        static func knee(for foot: SCNVector3, front: Bool) -> SCNVector3 {
            // Keep the front leg straight from shoulder to hoof throughout the step.
            if front {
                let ratio: Float = 0.27 / 0.61
                return SCNVector3(foot.x * ratio, foot.y * ratio, foot.z * ratio)
            }
            let x = Double(foot.x), y = Double(foot.y), z = Double(foot.z)
            let length = max(0.001, sqrt(x*x+y*y+z*z))
            let d = min(0.609, max(0.071, length))
            let ux = x/length, uy = y/length, uz = z/length
            let a = (0.27*0.27 - 0.34*0.34 + d*d)/(2*d)
            let height = sqrt(max(0, 0.27*0.27-a*a))
            // Project the bend direction onto the plane perpendicular to the leg.
            let sign = 1.0
            let bx = -uz*ux*sign, by = -uz*uy*sign, bz = (1-uz*uz)*sign
            let bl = max(0.001, sqrt(bx*bx+by*by+bz*bz))
            return SCNVector3(ux*a+bx/bl*height,uy*a+by/bl*height,uz*a+bz/bl*height)
        }

        func update(_ node: SCNNode, dt: Double, grazing: Float, crouch: Float = 0) {
            guard dt > 0 else { return }
            let position = node.position
            let moved = previousPosition.map { hypot(Double(position.x-$0.x),Double(position.z-$0.z)) } ?? 0
            let yaw = Double(node.eulerAngles.y)
            let turned = abs(atan2(sin(yaw-previousYaw),cos(yaw-previousYaw)))
            previousPosition = position; previousYaw = yaw
            let speed = min(0.8, moved/dt)
            let activity = max(speed, min(0.4, turned/dt*0.2))
            blend += (min(1, activity/0.5)-blend)*min(1,dt*6)
            phase += activity*dt*14
            func landing(_ index: Int) -> SCNVector3 {
                let local = SCNVector3(index%2 == 0 ? -0.14 : 0.14,0,index<2 ? -0.27 : 0.28)
                var point = node.convertPosition(local, to: nil)
                point.x -= Float(sin(yaw)*speed*0.25)
                point.z -= Float(cos(yaw)*speed*0.25)
                point.y = ForestTerrain.walkingHeight(point)+0.01
                return point
            }
            if feet.isEmpty || moved > 1 {
                feet = (0..<4).map(landing); swingIndex = nil
            }
            timer -= dt
            if let index = swingIndex {
                swingTime += dt
                let t = min(1,swingTime/0.12)
                let smooth = t*t*(3-2*t)
                feet[index] = SCNVector3(
                    Double(swingStart.x)+(Double(swingEnd.x-swingStart.x))*smooth,
                    Double(swingStart.y)+(Double(swingEnd.y-swingStart.y))*smooth+sin(.pi*t)*0.065,
                    Double(swingStart.z)+(Double(swingEnd.z-swingStart.z))*smooth)
                if t >= 1 { feet[index] = swingEnd; swingIndex = nil }
            }
            if swingIndex == nil && timer <= 0 {
                let scheduled = order[nextLeg]; nextLeg = (nextLeg+1)%4
                let errors = (0..<4).map { index -> Double in
                    let desired = landing(index)
                    return hypot(Double(desired.x-feet[index].x),Double(desired.z-feet[index].z))
                }
                let urgent = errors.indices.max(by: { errors[$0] < errors[$1] }) ?? scheduled
                let index = errors[urgent] > 0.22 ? urgent : scheduled
                let destination = landing(index)
                let error = hypot(Double(destination.x-feet[index].x),Double(destination.z-feet[index].z))
                if error > 0.025 {
                    swingIndex = index; swingStart = feet[index]; swingEnd = destination; swingTime = 0
                    timer = max(0.13,min(0.22,0.08/max(0.1,activity)))
                }
            }
            let bob = Float(sin(phase*2)*0.006*blend)
            // Lower the pelvis slightly on slopes rather than stretching a
            // planted leg beyond its anatomical length.
            var hipHeight = 0.565 + Double(bob) - Double(crouch)
            for index in 0..<4 {
                let local = node.convertPosition(feet[index], from: nil)
                let dx = Double(local.x) - (index%2 == 0 ? -0.14 : 0.14)
                let dz = Double(local.z) - (index<2 ? -0.27 : 0.28)
                let reach = sqrt(max(0.01,0.605*0.605-dx*dx-dz*dz))
                hipHeight = min(hipHeight,Double(local.y)+reach)
            }
            node.childNode(withName: "deerBody", recursively: false)?.position.y = Float(hipHeight-0.565)
            node.childNode(withName: "deerBody", recursively: false)?.eulerAngles.z = Float(sin(phase)*0.009*blend)
            let neck = node.childNode(withName: "neck", recursively: true)
            neck?.eulerAngles.x = grazing+Float(sin(phase+0.7)*0.025*blend)
            neck?.position.y = 0.66+grazing*0.12
            for index in 0..<4 {
                guard let leg = node.childNode(withName: "leg\(index)", recursively: false) else { continue }
                leg.position.y = Float(hipHeight)
                let foot = leg.convertPosition(feet[index], from: nil)
                let joint = Self.knee(for: foot, front: index<2)
                leg.childNode(withName: "knee", recursively: false)?.position = joint
                leg.childNode(withName: "hoof", recursively: false)?.position = foot
                func segment(_ name: String, from a: SCNVector3, to b: SCNVector3) {
                    guard let bone = leg.childNode(withName: name, recursively: false) else { return }
                    let dx=b.x-a.x,dy=b.y-a.y,dz=b.z-a.z
                    bone.position = SCNVector3((a.x+b.x)/2,(a.y+b.y)/2,(a.z+b.z)/2)
                    bone.scale.z = sqrt(dx*dx+dy*dy+dz*dz)
                    bone.look(at: leg.convertPosition(b, to: nil), up: SCNVector3(0,1,0), localFront: SCNVector3(0,0,-1))
                }
                segment("upperLeg", from: SCNVector3Zero, to: joint)
                segment("lowerLeg", from: joint, to: foot)
            }
        }
    }

    final class DeerWander {
        private let gait = DeerGait()
        private var currentSpeed = 0.0
        private var nextDrink = Double.random(in: 12...28)
        private var drinkSite: SCNVector3?
        private var drinking = false
        private var sipTime = 0.0

        static func drinkingSpot(from start: SCNVector3, radius: Double, obstacles: [SCNVector3]) -> SCNVector3? {
            let side = Double(start.x) < ForestTerrain.riverX(Double(start.z)) ? -1.0 : 1.0
            for offset in [0.0, 2, -2, 4, -4, 6, -6] {
                let z = Double(start.z) + offset
                guard abs(z) > 2.5 else { continue }
                let point = SCNVector3(ForestTerrain.riverX(z) + side * 1.66, 0.03, z)
                guard hypot(Double(point.x), Double(point.z)) < radius-1.2,
                      obstacles.allSatisfy({ hypot(Double($0.x-point.x), Double($0.z-point.z)) > 1.1 }),
                      clearPath(from: start, to: point, obstacles: obstacles) else { continue }
                return point
            }
            return nil
        }

        private func endDrinking(_ node: SCNNode) {
            drinking = false; drinkSite = nil; sipTime = 0
            nextDrink = clock + Double.random(in: 50...100)
            node.childNode(withName: "neck", recursively: true)?.position.z = -0.30
        }
        private var target: SCNVector3?
        private var route: [SCNVector3] = []
        private var nextCrossing = Double.random(in: 8...20)
        private var previousTime = 0.0
        private var clock = 0.0
        private var rest = 0.0
        private var restDuration = 1.0
        private var speed = Double.random(in: 0.45...0.7)

        static func clearPath(from start: SCNVector3, to end: SCNVector3, obstacles: [SCNVector3]) -> Bool {
            let dx = Double(end.x - start.x), dz = Double(end.z - start.z)
            let lengthSquared = dx * dx + dz * dz
            // Sample the whole segment so a destination on the opposite bank
            // never sends the animal through the water.
            let samples = max(1, Int(sqrt(lengthSquared) / 0.2) + 1)
            for sample in 1...samples {
                let t = Double(sample) / Double(samples)
                let point = SCNVector3(Double(start.x) + dx * t, 0.03, Double(start.z) + dz * t)
                if !ForestTerrain.walkable(point) { return false }
            }
            return obstacles.allSatisfy { obstacle in
                let ox = Double(obstacle.x - start.x), oz = Double(obstacle.z - start.z)
                let projection = lengthSquared > 0 ? max(0, min(1, (ox * dx + oz * dz) / lengthSquared)) : 0
                let nearest = hypot(ox - projection * dx, oz - projection * dz)
                // If a task plants a tree underneath an animal, let it step out safely.
                if hypot(ox, oz) < 1.05 { return ox * dx + oz * dz <= 0 }
                return nearest >= 1.05
            }
        }

        // A small grid finds a dry approach around trunks, then the bridge's
        // centre row supplies the only legal crossing of the water.
        static func crossingRoute(from start: SCNVector3, radius: Double, obstacles: [SCNVector3]) -> [SCNVector3] {
            struct Cell: Hashable { var x: Int; var z: Int }
            func point(_ c: Cell) -> SCNVector3 { SCNVector3(Double(c.x) + ForestTerrain.bridgeCenter, 0.03, Double(c.z)) }
            let side = Double(start.x) < ForestTerrain.riverX(Double(start.z)) ? -1 : 1
            let goal = Cell(x: -side * 4, z: 0)
            let origin = Cell(x: Int((Double(start.x) - ForestTerrain.bridgeCenter).rounded()), z: Int(Double(start.z).rounded()))
            let seeds = (-1...1).flatMap { x in (-1...1).map { Cell(x: origin.x+x, z: origin.z+$0) } }
                .filter { hypot(Double(point($0).x), Double(point($0).z)) < radius-1.2 && clearPath(from: start, to: point($0), obstacles: obstacles) }
            var queue = seeds
            var visited = Set(seeds)
            var parent: [Cell: Cell] = [:]
            var head = 0
            while head < queue.count && head < 16000 {
                let cell = queue[head]; head += 1
                if cell == goal {
                    var cells = [cell]; var cursor = cell
                    while let previous = parent[cursor] { cells.append(previous); cursor = previous }
                    let raw = cells.reversed().map(point)
                    var result: [SCNVector3] = []; var position = start; var index = 0
                    while index < raw.count {
                        var end = index
                        while end+1 < raw.count && clearPath(from: position, to: raw[end+1], obstacles: obstacles) { end += 1 }
                        result.append(raw[end]); position = raw[end]; index = end+1
                    }
                    return result
                }
                for offset in [Cell(x:1,z:0), Cell(x:-1,z:0), Cell(x:0,z:1), Cell(x:0,z:-1)] {
                    let next = Cell(x:cell.x+offset.x, z:cell.z+offset.z)
                    let destination = point(next)
                    guard !visited.contains(next), hypot(Double(destination.x), Double(destination.z)) < radius-1.2,
                          ForestTerrain.walkable(destination), clearPath(from: point(cell), to: destination, obstacles: obstacles) else { continue }
                    visited.insert(next); parent[next] = cell; queue.append(next)
                }
            }
            return []
        }

        func advance(_ node: SCNNode, elapsed: Double, radius: Double, obstacles: [SCNVector3]) {
            let dt = max(0, min(0.1, elapsed >= previousTime ? elapsed - previousTime : elapsed))
            previousTime = elapsed
            clock += dt
            let limit = max(1, radius - 1.2)
            let distance = hypot(Double(node.position.x), Double(node.position.z))
            if distance > limit {
                node.position.x *= Float(limit / distance)
                node.position.z *= Float(limit / distance)
                target = nil
            }
            if !ForestTerrain.walkable(node.position) {
                let z = max(-limit * 0.85, min(limit * 0.85, Double(node.position.z)))
                let side = Double(node.position.x) < ForestTerrain.riverX(z) ? -1.0 : 1.0
                node.position = SCNVector3(ForestTerrain.riverX(z) + side * 1.66, 0.03, z)
                target = nil
                route.removeAll()
            }
            if node.action(forKey: "touchReaction") != nil {
                currentSpeed = 0
                if drinkSite != nil { endDrinking(node); target = nil }
                gait.update(node, dt: dt, grazing: 0)
                return
            }
            if let retreat = node.childNode(withName: "touchRetreat", recursively: false) {
                let destination = retreat.position
                retreat.removeFromParentNode()
                if hypot(Double(destination.x), Double(destination.z)) <= limit,
                   Self.clearPath(from: node.position, to: destination, obstacles: obstacles) {
                    route.removeAll(); target = destination; rest = 0
                    speed = 0.65
                }
            }
            if drinking, let site = drinkSite {
                if hypot(Double(node.position.x-site.x), Double(node.position.z-site.z)) > 0.15 ||
                   obstacles.contains(where: { hypot(Double($0.x-site.x), Double($0.z-site.z)) < 1.1 }) {
                    endDrinking(node)
                } else {
                    let dx = ForestTerrain.riverX(Double(site.z)) - Double(node.position.x)
                    let yaw = atan2(-dx, 0.0)
                    let delta = atan2(sin(yaw-Double(node.eulerAngles.y)), cos(yaw-Double(node.eulerAngles.y)))
                    node.eulerAngles.y += Float(max(-dt*0.9, min(dt*0.9, delta)))
                    if abs(delta) < 0.08 { sipTime += dt }
                    let weight = max(0, min(1, min(sipTime/1.0, (7-sipTime)/1.0)))
                    let smooth = weight*weight*(3-2*weight)
                    // Lower the body and leg joints together; the neck socket stays attached.
                    gait.update(node, dt: dt, grazing: 0, crouch: Float(0.22*smooth))
                    // Rotate only around the fixed shoulder pivot; translating the
                    // neck's base here would pull it away from the torso socket.
                    let neck = node.childNode(withName: "neck", recursively: true)
                    neck?.eulerAngles.x = Float((-1.72 + sin(sipTime*5)*0.012)*smooth)
                    currentSpeed = 0
                    if sipTime >= 7 { endDrinking(node); rest = 1; restDuration = 1 }
                    return
                }
            }
            var walked = false
            var grazing: Float = 0
            if rest > 0 {
                rest = max(0, rest - dt)
                grazing = -Float(pow(sin(.pi * (1 - rest / restDuration)), 2)) * 1.15
            } else {
                if let destination = target,
                   hypot(Double(destination.x), Double(destination.z)) > limit || !Self.clearPath(from: node.position, to: destination, obstacles: obstacles) {
                    target = nil
                    if drinkSite != nil { endDrinking(node) }
                }
                if target == nil && route.isEmpty && clock >= nextDrink {
                    if let site = Self.drinkingSpot(from: node.position, radius: radius, obstacles: obstacles) {
                        drinkSite = site; target = site
                    } else { nextDrink = clock + 15 }
                }
                if target == nil && route.isEmpty && clock >= nextCrossing {
                    route = Self.crossingRoute(from: node.position, radius: radius, obstacles: obstacles)
                    nextCrossing = clock + Double.random(in: 35...65)
                }
                if target == nil && !route.isEmpty { target = route.removeFirst() }
                if target == nil {
                    for _ in 0..<64 {
                        let angle = Double.random(in: 0..<(2 * .pi))
                        let length = Double.random(in: 2...7)
                        let candidate = SCNVector3(Double(node.position.x) + cos(angle) * length, 0.03, Double(node.position.z) + sin(angle) * length)
                        if hypot(Double(candidate.x), Double(candidate.z)) <= limit,
                           Self.clearPath(from: node.position, to: candidate, obstacles: obstacles) {
                            target = candidate
                            speed = Double.random(in: 0.45...0.7)
                            break
                        }
                    }
                    if target == nil { restDuration = 1; rest = 1 }
                }
                if let destination = target {
                    let dx = Double(destination.x - node.position.x), dz = Double(destination.z - node.position.z)
                    let remaining = hypot(dx, dz)
                    let desiredYaw = atan2(-dx, -dz)
                    let difference = atan2(sin(desiredYaw - Double(node.eulerAngles.y)), cos(desiredYaw - Double(node.eulerAngles.y)))
                    node.eulerAngles.y += Float(max(-dt * 0.9, min(dt * 0.9, difference)))
                    // Turn first, then walk forward instead of sliding sideways.
                    let desiredSpeed = speed * min(1, remaining / 0.45) * max(0, 1-abs(difference)/0.4)
                    currentSpeed += (desiredSpeed-currentSpeed)*min(1,dt*5)
                    if abs(difference) < 0.4 && remaining > 0.001 {
                        let step = min(remaining, currentSpeed * dt)
                        node.position.x += Float(dx / remaining * step)
                        node.position.z += Float(dz / remaining * step)
                        walked = step > 0
                    }
                    if remaining < 0.04 {
                        if drinkSite != nil { drinking = true; sipTime = 0 }
                        target = nil
                        restDuration = route.isEmpty ? Double.random(in: 1.5...5.5) : 0
                        rest = restDuration
                    }
                }
            }
            node.position.y = ForestTerrain.walkingHeight(node.position)
            if !walked { currentSpeed *= max(0, 1-dt*7) }
            gait.update(node, dt: dt, grazing: grazing)
        }
    }

    private static func deer(_ index: Int) -> SCNNode {
        let root = SCNNode(); root.name = "deer\(index)"
        root.scale = SCNVector3(0.95, 0.95, 0.95)
        func material(_ color: UIColor, roughness: CGFloat = 0.9) -> SCNMaterial {
            let result = SCNMaterial(); result.diffuse.contents = color
            result.lightingModel = .physicallyBased; result.roughness.contents = roughness
            return result
        }
        let fur = material(UIColor(red: index == 0 ? 0.60 : 0.70, green: 0.43, blue: 0.25, alpha: 1))
        let cream = material(UIColor(red: 0.91, green: 0.85, blue: 0.69, alpha: 1))
        let dark = material(UIColor(red: 0.18, green: 0.13, blue: 0.085, alpha: 1))
        let eye = material(UIColor(red: 0.045, green: 0.032, blue: 0.025, alpha: 1), roughness: 0.2)
        let earPink = material(UIColor(red: 0.57, green: 0.39, blue: 0.32, alpha: 1))
        @discardableResult
        func oval(_ parent: SCNNode, _ radius: CGFloat, _ scale: SCNVector3, _ position: SCNVector3, _ material: SCNMaterial) -> SCNNode {
            let shape = SCNSphere(radius: radius); shape.segmentCount = 18; shape.materials = [material]
            let node = SCNNode(geometry: shape); node.scale = scale; node.position = position
            parent.addChildNode(node); return node
        }
        func bone(_ parent: SCNNode, from a: SCNVector3, to b: SCNVector3, width: CGFloat, material: SCNMaterial) {
            let dx=b.x-a.x, dy=b.y-a.y, dz=b.z-a.z
            let shape = SCNCone(topRadius: width*0.72, bottomRadius: width, height: CGFloat(sqrt(dx*dx+dy*dy+dz*dz)))
            shape.radialSegmentCount = 10; shape.materials = [material]
            let pivot = SCNNode(); pivot.position = SCNVector3((a.x+b.x)/2,(a.y+b.y)/2,(a.z+b.z)/2)
            pivot.look(at: b)
            let node = SCNNode(geometry: shape); node.eulerAngles.x = .pi/2
            pivot.addChildNode(node); parent.addChildNode(pivot)
        }
        // Slender torso, stronger shoulders and haunches, with a pale underside.
        oval(root, 0.29, SCNVector3(0.70,0.77,1.58), SCNVector3(0,0.74,0), fur)
        oval(root, 0.22, SCNVector3(0.74,0.57,1.57), SCNVector3(0,0.61,0.015), cream)
        oval(root, 0.18, SCNVector3(0.95,1.25,0.95), SCNVector3(0,0.71,-0.29), fur)
        oval(root, 0.19, SCNVector3(0.98,1.10,1.08), SCNVector3(0,0.72,0.28), fur)
        for side in [-1.0,1.0] {
            oval(root, 0.12, SCNVector3(0.12,0.27,2.45), SCNVector3(side*0.205,0.67,0.01), dark)
            oval(root, 0.12, SCNVector3(0.12,0.23,2.35), SCNVector3(side*0.205,0.63,0.01), cream)
        }
        for legIndex in 0..<4 {
            let front = legIndex < 2
            let hip = SCNNode(); hip.name = "leg\(legIndex)"
            // Nudged 2% closer to the body's centerline so the legs sit a
            // touch tighter under the torso.
            hip.position = SCNVector3(legIndex % 2 == 0 ? -0.14 * 0.98 : 0.14 * 0.98, 0.565, front ? -0.27 : 0.28)
            for (name, width) in [("upperLeg", front ? 0.038 : 0.050), ("lowerLeg", 0.022)] {
                let pivot = SCNNode(); pivot.name = name
                let shape = SCNCone(topRadius: width*0.72, bottomRadius: width, height: 1)
                shape.radialSegmentCount = 10; shape.materials = [fur]
                let segment = SCNNode(geometry: shape); segment.eulerAngles.x = .pi/2
                pivot.addChildNode(segment); hip.addChildNode(pivot)
            }
            oval(hip, 0.03, SCNVector3(1,1.1,1), SCNVector3(0,-0.25,0), fur).name = "knee"
            oval(hip, 0.036, SCNVector3(0.78,1.05,1.5), SCNVector3(0,-0.555,0), dark).name = "hoof"
            root.addChildNode(hip)
        }
        let neck = SCNNode(); neck.name = "neck"; neck.position = SCNVector3(0,0.66,-0.30)
        oval(neck, 0.11, SCNVector3(0.88,2.15,0.92), SCNVector3(0,0.20,-0.045), fur).eulerAngles.x = -0.25
        oval(neck, 0.078, SCNVector3(0.65,2.1,0.32), SCNVector3(0,0.18,-0.13), cream).eulerAngles.x = -0.25
        oval(neck, 0.105, SCNVector3(0.82,1.13,1.7), SCNVector3(0,0.42,-0.12), fur)
        oval(neck, 0.075, SCNVector3(0.75,0.77,1.37), SCNVector3(0,0.365,-0.27), cream)
        oval(neck, 0.041, SCNVector3(1,0.66,0.72), SCNVector3(0,0.37,-0.351), dark)
        for side in [-1.0,1.0] {
            oval(neck, 0.04, SCNVector3(0.20,1.22,1.05), SCNVector3(side*0.088,0.425,-0.185), cream)
            oval(neck, 0.020, SCNVector3(0.50,0.8,1), SCNVector3(side*0.098,0.435,-0.192), eye)
            oval(neck, 0.022, SCNVector3(0.35,0.75,2.9), SCNVector3(side*0.068,0.395,-0.262), dark).eulerAngles.x = -0.45
            let ear = SCNNode(); ear.name = side < 0 ? "earLeft" : "earRight"
            ear.position = SCNVector3(side*0.095,0.50,-0.075); ear.eulerAngles.z = Float(side)*(-0.65)
            oval(ear, 0.070, SCNVector3(0.63,1.75,0.25), SCNVector3(0,0.07,0), fur)
            oval(ear, 0.052, SCNVector3(0.6,1.75,0.12), SCNVector3(0,0.072,-0.018), earPink)
            neck.addChildNode(ear)
            let length = index == 0 ? 0.31 : 0.22
            var previous = SCNVector3(side*0.05,0.51,-0.105)
            for segment in 1...7 {
                let t = Double(segment)/7
                let next = SCNVector3(side*(0.05+0.022*sin(t * .pi)),0.51+length*t,-0.105+0.07*sin(t * .pi*0.9))
                bone(neck, from: previous, to: next, width: CGFloat(0.019*(1-t*0.85)), material: dark)
                previous = next
            }
        }
        root.addChildNode(neck)
        let tail = oval(root, 0.075, SCNVector3(0.42,0.48,1.5), SCNVector3(0,0.76,0.48), fur)
        tail.name = "tail"
        oval(tail, 0.045, SCNVector3(0.75,0.8,1.1), SCNVector3(0,0,0.075), dark)
        let body = SCNNode(); body.name = "deerBody"
        for child in root.childNodes where child.name?.hasPrefix("leg") != true {
            child.removeFromParentNode(); body.addChildNode(child)
        }
        root.addChildNode(body)
        return root
    }

    private static func updateRabbits(_ root: SCNNode, moving: Bool) {
        let rabbits: SCNNode
        if let existing = root.childNode(withName: "forestRabbits", recursively: false) { rabbits = existing }
        else {
            rabbits = SCNNode(); rabbits.name = "forestRabbits"
            for index in 0..<3 {
                let animal = rabbit(index)
                let z = Double(index - 1) * 4
                let side = index == 1 ? -1.0 : 1.0
                animal.position = SCNVector3(ForestTerrain.riverX(z) + side * 5, 0.03, z)
                rabbits.addChildNode(animal)
            }
            root.addChildNode(rabbits)
        }
        for animal in rabbits.childNodes {
            if moving {
                guard animal.action(forKey: "rabbitWander") == nil else { continue }
                let wander = RabbitWander()
                animal.runAction(.repeatForever(.customAction(duration: 600) { [weak root] node, elapsed in
                    guard let root else { return }
                    let radius = Double(root.childNode(withName: "ground", recursively: false)?.scale.x ?? 1) * 14
                    let obstacles = (root.childNode(withName: "plants", recursively: false)?.childNodes.map { $0.position } ?? []) + WaterMillAsset.obstacles(in: root) + ForestSwingAsset.obstacles(in: root)
                    let burrow = root.childNode(withName: "rabbitBurrow", recursively: false)?.position
                    wander.advance(node, elapsed: Double(elapsed), radius: radius, obstacles: obstacles, burrow: burrow)
                    // Keep this rabbit from visually settling on top of
                    // another rabbit or a deer.
                    let otherRabbits = root.childNode(withName: "forestRabbits", recursively: false)?.childNodes.compactMap { $0 !== node ? $0.position : nil } ?? []
                    separate(node, from: otherRabbits, minDistance: 0.4)
                    let deer = root.childNode(withName: "forestAnimals", recursively: false)?.childNodes.map { $0.position } ?? []
                    separate(node, from: deer, minDistance: 0.65)
                }), forKey: "rabbitWander")
            } else {
                animal.removeAction(forKey: "rabbitWander")
                animal.isHidden = false
                animal.position.y = ForestTerrain.walkingHeight(animal.position)
                let body = animal.childNode(withName: "rabbitBody", recursively: false)
                body?.eulerAngles.x = 0
                body?.scale = SCNVector3(1, 1, 1)
                for name in ["earLeft", "earRight", "hindLegLeft", "hindLegRight", "frontLegLeft", "frontLegRight"] {
                    animal.childNode(withName: name, recursively: true)?.eulerAngles.x = 0
                }
            }
        }
    }

    final class RabbitWander {
        private var previousTime = 0.0
        private var pause = Double.random(in: 0...2)
        private var target: SCNVector3?
        private var hopStart = SCNVector3Zero
        private var hopEnd = SCNVector3Zero
        private var hopTime = 0.0
        private var hopping = false
        private let idlePhase = Double.random(in: 0..<(2 * .pi))
        private var noseBaseScale: SCNVector3?
        private var clock = 0.0
        private var nextBurrowVisit = Double.random(in: 15...40)
        private var inBurrow = false
        private var burrowTimer = 0.0

        private func resetPose(body: SCNNode?, hindLegs: [SCNNode], frontLegs: [SCNNode]) {
            body?.eulerAngles.x = 0
            body?.scale = SCNVector3(1, 1, 1)
            for leg in hindLegs { leg.eulerAngles.x = 0 }
            for leg in frontLegs { leg.eulerAngles.x = 0 }
        }

        func advance(_ node: SCNNode, elapsed: Double, radius: Double, obstacles: [SCNVector3], burrow: SCNVector3?) {
            let dt = max(0, min(0.1, elapsed >= previousTime ? elapsed-previousTime : elapsed))
            previousTime = elapsed
            clock += dt
            // While tucked inside the burrow there is nothing to animate;
            // just wait out the visit, then pop back out at the entrance.
            if inBurrow {
                burrowTimer -= dt
                if burrowTimer <= 0 {
                    inBurrow = false
                    node.isHidden = false
                    if let burrow { node.position = burrow }
                    node.position.y = ForestTerrain.walkingHeight(node.position)
                    nextBurrowVisit = clock + Double.random(in: 45...100)
                }
                return
            }
            let limit = max(1, radius-1.2)
            let body = node.childNode(withName: "rabbitBody", recursively: false)
            let ears = ["earLeft", "earRight"].compactMap { node.childNode(withName: $0, recursively: true) }
            let hindLegs = ["hindLegLeft", "hindLegRight"].compactMap { node.childNode(withName: $0, recursively: true) }
            let frontLegs = ["frontLegLeft", "frontLegRight"].compactMap { node.childNode(withName: $0, recursively: true) }
            let nose = node.childNode(withName: "nose", recursively: true)
            // Recover if removing tasks shrinks the island around a rabbit.
            let distance = hypot(Double(node.position.x), Double(node.position.z))
            if distance > limit {
                node.position.x *= Float(limit/distance); node.position.z *= Float(limit/distance)
                target = nil; hopping = false
            }
            if !ForestTerrain.walkable(node.position) {
                let z = max(-limit*0.7, min(limit*0.7, Double(node.position.z)))
                let side = Double(node.position.x) < ForestTerrain.riverX(z) ? -1.0 : 1.0
                node.position = SCNVector3(ForestTerrain.riverX(z)+side*1.66,0.03,z)
                target = nil; hopping = false
            }
            if let retreat = node.childNode(withName: "touchRetreat", recursively: false) {
                let destination = retreat.position
                retreat.removeFromParentNode()
                if hypot(Double(destination.x), Double(destination.z)) <= limit,
                   DeerWander.clearPath(from: node.position, to: destination, obstacles: obstacles) {
                    target = destination; hopping = false; pause = 0
                }
            }
            if let destination = target,
               hypot(Double(destination.x),Double(destination.z)) > limit ||
               !DeerWander.clearPath(from: node.position, to: destination, obstacles: obstacles) {
                target = nil; hopping = false; pause = 0.5
            }
            if target == nil {
                node.position.y = ForestTerrain.walkingHeight(node.position)
                resetPose(body: body, hindLegs: hindLegs, frontLegs: frontLegs)
                // A resting rabbit still breathes, twitches its ears and wiggles its nose.
                let breathe = Float(1 + sin(elapsed * 2.1 + idlePhase) * 0.02)
                body?.scale = SCNVector3(breathe, breathe, breathe)
                let flick = Float(max(0, sin(elapsed * 0.6 + idlePhase) - 0.95) * 8)
                for ear in ears { ear.eulerAngles.x = -flick }
                // Scale the nose relative to its own tiny base size, never absolute,
                // or the wiggle balloons it into the sphere's full unit radius.
                if noseBaseScale == nil { noseBaseScale = nose?.scale }
                if let base = noseBaseScale {
                    let noseWiggle = Float(1 + sin(elapsed * 5 + idlePhase) * 0.18)
                    nose?.scale = SCNVector3(base.x*noseWiggle, base.y*noseWiggle, base.z*noseWiggle)
                }
                pause = max(0, pause-dt)
                guard pause == 0 else { return }
                if let burrow, clock >= nextBurrowVisit,
                   hypot(Double(burrow.x), Double(burrow.z)) < limit,
                   DeerWander.clearPath(from: node.position, to: burrow, obstacles: obstacles) {
                    target = burrow
                } else {
                    for _ in 0..<32 {
                        let angle = Double.random(in: 0..<(2 * .pi))
                        let distance = Double.random(in: 0.65...1.25)
                        let candidate = SCNVector3(Double(node.position.x)+cos(angle)*distance, 0.03, Double(node.position.z)+sin(angle)*distance)
                        if hypot(Double(candidate.x),Double(candidate.z)) < limit,
                           DeerWander.clearPath(from: node.position, to: candidate, obstacles: obstacles) {
                            target = candidate; break
                        }
                    }
                    if target == nil { pause = 1 }
                }
            }
            guard let destination = target else { return }
            if !hopping && pause > 0 { pause = max(0, pause-dt); return }
            if !hopping {
                let yaw = atan2(-Double(destination.x-node.position.x), -Double(destination.z-node.position.z))
                let delta = atan2(sin(yaw-Double(node.eulerAngles.y)),cos(yaw-Double(node.eulerAngles.y)))
                node.eulerAngles.y += Float(max(-dt*3, min(dt*3,delta)))
                guard abs(delta) < 0.08 else { return }
                hopping = true; hopTime = 0; hopStart = node.position
                let dx = Double(destination.x-node.position.x), dz = Double(destination.z-node.position.z)
                let length = max(0.001, hypot(dx,dz))
                let fraction = min(1, 1.0/length)
                hopEnd = SCNVector3(Double(node.position.x)+dx*fraction, 0.03, Double(node.position.z)+dz*fraction)
            }
            hopTime += dt
            let duration = 0.6
            let t = min(1,hopTime/duration)
            let travel = t*t*(3-2*t)
            node.position.x = hopStart.x + (hopEnd.x-hopStart.x)*Float(travel)
            node.position.z = hopStart.z + (hopEnd.z-hopStart.z)*Float(travel)
            let arc = sin(.pi*t)
            node.position.y = ForestTerrain.walkingHeight(node.position) + Float(arc*0.18)
            // Squash at takeoff and landing, stretch through mid-air; hind legs kick
            // back for the push-off while front paws reach forward, like a real hop.
            let stretch = Float(arc)
            body?.eulerAngles.x = Float(-arc*0.4)
            body?.scale = SCNVector3(1-stretch*0.06, 1+stretch*0.18, 1-stretch*0.06)
            for leg in hindLegs { leg.eulerAngles.x = -stretch*0.95 }
            for leg in frontLegs { leg.eulerAngles.x = stretch*0.55 }
            let earTrail = Float(sin(.pi * max(0, min(1, t - 0.06))))
            for ear in ears { ear.eulerAngles.x = -earTrail*0.55 }
            if t >= 1 {
                if hypot(Double(destination.x-node.position.x),Double(destination.z-node.position.z)) > 0.04 {
                    hopping = false; pause = Double.random(in: 0.35...0.7)
                    resetPose(body: body, hindLegs: hindLegs, frontLegs: frontLegs)
                    for ear in ears { ear.eulerAngles.x = 0 }
                    return
                }
                let arrivedAtBurrow = burrow.map { hypot(Double(destination.x-$0.x), Double(destination.z-$0.z)) < 0.05 } ?? false
                target = nil; hopping = false
                resetPose(body: body, hindLegs: hindLegs, frontLegs: frontLegs)
                for ear in ears { ear.eulerAngles.x = 0 }
                if arrivedAtBurrow {
                    inBurrow = true
                    burrowTimer = Double.random(in: 4...9)
                    node.isHidden = true
                } else {
                    pause = Double.random(in: 0.35...1.8)
                }
            }
        }
    }

    // A soft radial-gradient texture for the hole's opening: near-black at the
    // center, fading through a warm dark brown, then to transparent at the
    // rim so it blends into the dirt mound rather than reading as a hard disc.
    private static func burrowHoleTexture() -> UIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 2
        return UIGraphicsImageRenderer(size: CGSize(width: 256, height: 200), format: format).image { renderer in
            let ctx = renderer.cgContext
            let center = CGPoint(x: 128, y: 104)
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                          colors: [UIColor(red: 0.015, green: 0.01, blue: 0.01, alpha: 1).cgColor,
                                                    UIColor(red: 0.05, green: 0.035, blue: 0.02, alpha: 1).cgColor,
                                                    UIColor(red: 0.12, green: 0.08, blue: 0.05, alpha: 0.55).cgColor,
                                                    UIColor(red: 0.12, green: 0.08, blue: 0.05, alpha: 0).cgColor] as CFArray,
                                          locations: [0, 0.45, 0.8, 1]) {
                ctx.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: 112, options: [])
            }
        }
    }

    // A burrow entrance in one corner of the island. Its position is set
    // relative to the current island radius by ForestSceneView, alongside
    // the ground, soil and border, so it stays in its corner as the island grows.
    static func rabbitBurrow() -> SCNNode {
        let root = SCNNode(); root.name = "rabbitBurrow"
        let dirtTones = [
            UIColor(red: 0.47, green: 0.35, blue: 0.22, alpha: 1),
            UIColor(red: 0.40, green: 0.29, blue: 0.18, alpha: 1),
            UIColor(red: 0.35, green: 0.25, blue: 0.15, alpha: 1)
        ]
        func dirtMaterial(_ tone: UIColor) -> SCNMaterial {
            let m = SCNMaterial()
            m.diffuse.contents = tone
            m.lightingModel = .physicallyBased
            m.roughness.contents = 0.95
            m.metalness.contents = 0.0
            return m
        }
        let tuft = SCNMaterial(); tuft.diffuse.contents = UIColor(red: 0.34, green: 0.47, blue: 0.24, alpha: 1)
        tuft.lightingModel = .lambert
        let stone = SCNMaterial(); stone.diffuse.contents = UIColor(red: 0.55, green: 0.55, blue: 0.52, alpha: 1)
        stone.lightingModel = .physicallyBased
        stone.roughness.contents = 0.8

        // An irregular mound of turned-up earth built from several overlapping
        // bumps instead of one symmetric ellipsoid, so it reads as freshly dug
        // soil rather than a smooth sticker.
        let bumps: [(Float, Float, Float, Float)] = [
            (0, 0.02, -0.06, 0.5), (-0.30, 0.01, 0.08, 0.34),
            (0.32, 0.01, 0.10, 0.32), (0, 0.0, -0.38, 0.3), (-0.12, 0.02, -0.22, 0.26)
        ]
        for (index, bump) in bumps.enumerated() {
            let (x, y, z, r) = bump
            let sphere = SCNSphere(radius: CGFloat(r)); sphere.segmentCount = 10
            sphere.materials = [dirtMaterial(dirtTones[index % dirtTones.count])]
            let node = SCNNode(geometry: sphere)
            node.scale = SCNVector3(1.25, 0.40, 1.05)
            node.position = SCNVector3(x, y, z)
            root.addChildNode(node)
        }

        // The hole itself: a flat, unlit disc with a soft dark gradient so it
        // reads as an actual void with depth rather than a lit dome poking up.
        let holePlane = SCNPlane(width: 0.62, height: 0.5)
        let holeMaterial = SCNMaterial()
        holeMaterial.diffuse.contents = burrowHoleTexture()
        holeMaterial.lightingModel = .constant
        holeMaterial.isDoubleSided = true
        holePlane.materials = [holeMaterial]
        let holeNode = SCNNode(geometry: holePlane)
        holeNode.eulerAngles.x = -.pi / 2
        // Sits just in front of the mound, clear of its bumps, so it isn't
        // swallowed by the solid dirt geometry behind it.
        holeNode.position = SCNVector3(0, 0.035, 0.58)
        root.addChildNode(holeNode)

        // A lip of darker packed earth right at the entrance, so the hole
        // doesn't float directly on top of the lighter mound color.
        let lip = SCNTorus(ringRadius: 0.19, pipeRadius: 0.05)
        lip.materials = [dirtMaterial(UIColor(red: 0.28, green: 0.20, blue: 0.12, alpha: 1))]
        let lipNode = SCNNode(geometry: lip)
        lipNode.scale = SCNVector3(1.05, 0.32, 0.85)
        lipNode.position = SCNVector3(0, 0.02, 0.58)
        root.addChildNode(lipNode)

        // A couple of loose pebbles and a stray twig, kicked up by the digging.
        let pebblePositions: [(Float, Float, Float)] = [(-0.42, 0.05, 0.4), (0.4, 0.04, 0.3), (0.12, 0.04, 0.72)]
        for (x, y, z) in pebblePositions {
            let radius = CGFloat.random(in: 0.05...0.09)
            let pebble = SCNSphere(radius: radius); pebble.segmentCount = 8; pebble.materials = [stone]
            let node = SCNNode(geometry: pebble)
            node.scale = SCNVector3(1, 0.7, 1)
            node.position = SCNVector3(x, y, z)
            root.addChildNode(node)
        }

        // Loose tufts of grass ringing the mound for detail.
        for i in 0..<6 {
            let angle = Double(i) * 1.05
            let x = Float(cos(angle) * 0.52), z = Float(sin(angle) * 0.46) - 0.08
            let blade = SCNCone(topRadius: 0, bottomRadius: 0.045, height: 0.2 + CGFloat(i % 3) * 0.04)
            blade.radialSegmentCount = 5; blade.materials = [tuft]
            let node = SCNNode(geometry: blade)
            node.position = SCNVector3(x, 0.1, z)
            node.eulerAngles.z = Float(cos(angle)) * 0.3
            node.eulerAngles.x = Float(sin(angle)) * 0.15
            root.addChildNode(node)
        }
        return root
    }

    // A small lamp post accessory: at night it's a warm, glowing lantern; by
    // day the same post carries a little birdhouse instead. Both toppers are
    // built once and swapped by visibility in `update(_:...)` so there's no
    // rebuild cost on the day/night transition.
    static func lampPost() -> SCNNode {
        let root = SCNNode(); root.name = "lampPost"

        let woodMaterial = SCNMaterial()
        woodMaterial.diffuse.contents = UIColor(red: 0.36, green: 0.24, blue: 0.15, alpha: 1)
        woodMaterial.lightingModel = .physicallyBased
        woodMaterial.roughness.contents = 0.8

        let poleHeight: CGFloat = 1.7
        let pole = SCNCylinder(radius: 0.035, height: poleHeight)
        pole.materials = [woodMaterial]
        let poleNode = SCNNode(geometry: pole)
        poleNode.position.y = Float(poleHeight / 2)
        root.addChildNode(poleNode)

        // A small round base so the post reads as planted in the ground.
        let base = SCNCylinder(radius: 0.09, height: 0.04)
        base.materials = [woodMaterial]
        let baseNode = SCNNode(geometry: base)
        baseNode.position.y = 0.02
        root.addChildNode(baseNode)

        let topY = Float(poleHeight)

        // MARK: Night — a warm, glowing lantern.
        let lanternTop = SCNNode(); lanternTop.name = "lanternTop"
        let frameMaterial = SCNMaterial()
        frameMaterial.diffuse.contents = UIColor(red: 0.16, green: 0.14, blue: 0.12, alpha: 1)
        frameMaterial.lightingModel = .physicallyBased
        frameMaterial.roughness.contents = 0.5
        frameMaterial.metalness.contents = 0.6

        let glassMaterial = SCNMaterial()
        glassMaterial.diffuse.contents = UIColor(red: 1, green: 0.85, blue: 0.55, alpha: 0.92)
        glassMaterial.emission.contents = UIColor(red: 1, green: 0.72, blue: 0.35, alpha: 1)
        glassMaterial.lightingModel = .constant
        glassMaterial.isDoubleSided = true

        let bulb = SCNSphere(radius: 0.09); bulb.segmentCount = 10; bulb.materials = [glassMaterial]
        let bulbNode = SCNNode(geometry: bulb)
        bulbNode.position = SCNVector3(0, topY + 0.16, 0)
        lanternTop.addChildNode(bulbNode)

        // Thin cage bars around the glowing bulb.
        for i in 0..<4 {
            let angle = Double(i) * (.pi / 2)
            let bar = SCNCylinder(radius: 0.012, height: 0.22)
            bar.materials = [frameMaterial]
            let node = SCNNode(geometry: bar)
            node.position = SCNVector3(Float(cos(angle)) * 0.09, topY + 0.16, Float(sin(angle)) * 0.09)
            lanternTop.addChildNode(node)
        }
        // A peaked cap on top.
        let cap = SCNCone(topRadius: 0.01, bottomRadius: 0.1, height: 0.07)
        cap.materials = [frameMaterial]
        let capNode = SCNNode(geometry: cap)
        capNode.position = SCNVector3(0, topY + 0.30, 0)
        lanternTop.addChildNode(capNode)

        let lanternLight = SCNNode(); lanternLight.name = "lanternLight"
        lanternLight.light = SCNLight()
        lanternLight.light?.type = .omni
        lanternLight.light?.intensity = 180
        lanternLight.light?.color = UIColor(red: 1.0, green: 0.75, blue: 0.45, alpha: 1)
        lanternLight.light?.attenuationStartDistance = 0.5
        lanternLight.light?.attenuationEndDistance = 4.0
        lanternLight.light?.castsShadow = false
        lanternLight.position = SCNVector3(0, topY + 0.16, 0)
        lanternTop.addChildNode(lanternLight)

        lanternTop.isHidden = true // corrected every update by ForestLife.update(night:)
        root.addChildNode(lanternTop)

        // MARK: Day — a small birdhouse.
        let birdhouseTop = SCNNode(); birdhouseTop.name = "birdhouseTop"
        let houseMaterial = SCNMaterial()
        houseMaterial.diffuse.contents = UIColor(red: 0.78, green: 0.63, blue: 0.42, alpha: 1)
        houseMaterial.lightingModel = .physicallyBased
        houseMaterial.roughness.contents = 0.85
        let roofMaterial = SCNMaterial()
        roofMaterial.diffuse.contents = UIColor(red: 0.55, green: 0.20, blue: 0.16, alpha: 1)
        roofMaterial.lightingModel = .physicallyBased
        roofMaterial.roughness.contents = 0.7

        let body = SCNBox(width: 0.26, height: 0.22, length: 0.24, chamferRadius: 0.015)
        body.materials = [houseMaterial]
        let bodyNode = SCNNode(geometry: body)
        bodyNode.position = SCNVector3(0, topY + 0.12, 0)
        birdhouseTop.addChildNode(bodyNode)

        // A simple 4-sided pyramid roof, built from a cone with 4 radial segments.
        let roof = SCNCone(topRadius: 0.001, bottomRadius: 0.22, height: 0.16)
        roof.radialSegmentCount = 4
        roof.materials = [roofMaterial]
        let roofNode = SCNNode(geometry: roof)
        roofNode.eulerAngles.y = Float.pi / 4
        roofNode.position = SCNVector3(0, topY + 0.30, 0)
        birdhouseTop.addChildNode(roofNode)

        // A round entrance hole with a tiny perch stick below it.
        let entranceMaterial = SCNMaterial()
        entranceMaterial.diffuse.contents = UIColor(red: 0.08, green: 0.05, blue: 0.04, alpha: 1)
        entranceMaterial.lightingModel = .lambert
        let entrance = SCNCylinder(radius: 0.035, height: 0.01)
        entrance.materials = [entranceMaterial]
        let entranceNode = SCNNode(geometry: entrance)
        entranceNode.eulerAngles.x = Float.pi / 2
        entranceNode.position = SCNVector3(0, topY + 0.14, 0.121)
        birdhouseTop.addChildNode(entranceNode)

        let perch = SCNCylinder(radius: 0.008, height: 0.07)
        perch.materials = [woodMaterial]
        let perchNode = SCNNode(geometry: perch)
        perchNode.eulerAngles.z = Float.pi / 2
        perchNode.position = SCNVector3(0, topY + 0.08, 0.13)
        birdhouseTop.addChildNode(perchNode)

        birdhouseTop.isHidden = false // corrected every update by ForestLife.update(night:)
        root.addChildNode(birdhouseTop)

        return root
    }

    private static func rabbit(_ index: Int) -> SCNNode {
        let root = SCNNode(); root.name = "rabbit\(index)"
        // A small litter-like variety: each rabbit a slightly different size
        // and a slightly different shade within the same pale pink family.
        let size = Float(0.88 + 0.06 * Double(index % 3))
        root.scale = SCNVector3(size, size, size)
        let shade = 1 - 0.05 * Double(index % 3)
        let body = SCNNode(); body.name = "rabbitBody"; root.addChildNode(body)
        let coat = SCNMaterial(); coat.diffuse.contents = UIColor(red: 0.98*shade, green: 0.82*shade, blue: 0.87*shade, alpha: 1)
        coat.lightingModel = .physicallyBased; coat.roughness.contents = 0.95
        let cream = SCNMaterial(); cream.diffuse.contents = UIColor(red: 0.995, green: 0.97, blue: 0.98, alpha: 1)
        cream.lightingModel = .physicallyBased; cream.roughness.contents = 0.9
        let inner = SCNMaterial(); inner.diffuse.contents = UIColor(red: 0.72, green: 0.28, blue: 0.42, alpha: 1)
        let dark = SCNMaterial(); dark.diffuse.contents = UIColor(red: 0.10, green: 0.08, blue: 0.09, alpha: 1)
        @discardableResult
        func oval(_ parent: SCNNode, _ position: SCNVector3, _ scale: SCNVector3, _ material: SCNMaterial) -> SCNNode {
            let sphere = SCNSphere(radius: 1); sphere.segmentCount = 14; sphere.materials = [material]
            let node = SCNNode(geometry: sphere); node.position = position; node.scale = scale
            parent.addChildNode(node); return node
        }
        oval(body, SCNVector3(0,0.23,0.06), SCNVector3(0.18,0.20,0.29), coat)
        oval(body, SCNVector3(0,0.34,-0.20), SCNVector3(0.14,0.145,0.14), coat)
        oval(body, SCNVector3(0,0.245,0.34), SCNVector3(0.11,0.10,0.12), cream)
        oval(body, SCNVector3(0,0.30,-0.33), SCNVector3(0.033,0.025,0.025), inner).name = "nose"
        // A rounder, fluffier tail than a single flat blob.
        let tail = SCNNode(); tail.name = "tail"; tail.position = SCNVector3(0,0.26,0.37); body.addChildNode(tail)
        oval(tail, SCNVector3(0,0,0), SCNVector3(0.075,0.075,0.075), cream)
        oval(tail, SCNVector3(0,0.02,-0.02), SCNVector3(0.05,0.05,0.05), cream)
        for side in [-1.0,1.0] {
            oval(body, SCNVector3(side*0.125,0.38,-0.255), SCNVector3(0.022,0.029,0.025), dark)
            let ear = SCNNode(); ear.name = side < 0 ? "earLeft" : "earRight"
            ear.position = SCNVector3(side*0.065,0.44,-0.18)
            ear.eulerAngles.z = Float(-side*0.15); body.addChildNode(ear)
            oval(ear, SCNVector3(0,0.14,0), SCNVector3(0.050,0.20,0.042), coat)
            oval(ear, SCNVector3(0,0.145,-0.034), SCNVector3(0.028,0.145,0.012), inner)
            // Hind leg: bigger, tucked under the haunch, kicks back on takeoff.
            let hind = SCNNode(); hind.name = side < 0 ? "hindLegLeft" : "hindLegRight"
            hind.position = SCNVector3(side*0.115,0.115,0.19); body.addChildNode(hind)
            oval(hind, SCNVector3(0,-0.03,0.01), SCNVector3(0.065,0.09,0.075), coat)
            oval(hind, SCNVector3(0,-0.095,0.05), SCNVector3(0.05,0.045,0.14), coat)
            // Front paw: small, tucked beneath the chest, reaches forward mid-hop.
            let front = SCNNode(); front.name = side < 0 ? "frontLegLeft" : "frontLegRight"
            front.position = SCNVector3(side*0.075,0.12,-0.15); body.addChildNode(front)
            oval(front, SCNVector3(0,-0.05,0), SCNVector3(0.04,0.075,0.045), coat)
        }
        return root
    }

    private static func butterfly(_ index: Int) -> SCNNode {
        let root = SCNNode()
        root.position = SCNVector3(cos(Double(index) * 2.4) * 5, 1.2 + Double(index % 4) * 0.6, sin(Double(index) * 2.4) * 5)
        let palettes: [(UIColor, UIColor)] = [
            (UIColor(red: 0.95, green: 0.71, blue: 0.32, alpha: 1), UIColor(red: 0.47, green: 0.26, blue: 0.10, alpha: 1)),
            (UIColor(red: 0.46, green: 0.72, blue: 0.86, alpha: 1), UIColor(red: 0.20, green: 0.32, blue: 0.52, alpha: 1)),
            (UIColor(red: 0.85, green: 0.52, blue: 0.65, alpha: 1), UIColor(red: 0.52, green: 0.22, blue: 0.36, alpha: 1))
        ]
        let (mainColor, edgeColor) = palettes[index % palettes.count]
        // A simple base-to-tip gradient reads as more detail on a low-poly
        // wing than a single flat fill.
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let wingGradient = UIGraphicsImageRenderer(size: CGSize(width: 48, height: 6), format: format).image { ctx in
            let colors = [mainColor.cgColor, edgeColor.cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                ctx.cgContext.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 3), end: CGPoint(x: 48, y: 3), options: [])
            }
        }
        let edge = SCNMaterial(); edge.diffuse.contents = edgeColor
        edge.lightingModel = .lambert; edge.isDoubleSided = true
        let dark = SCNMaterial(); dark.diffuse.contents = UIColor(red: 0.16, green: 0.13, blue: 0.11, alpha: 1)
        for side in [-1.0, 1.0] {
            let hinge = SCNNode()
            hinge.name = side < 0 ? "leftWing" : "rightWing"
            // The hinge sits right at the body's edge, not at the centerline,
            // so flapping pivots at the actual seam instead of swinging the
            // wing's inner edge away from the body and leaving a visible gap.
            hinge.position = SCNVector3(Float(side) * 0.02, 0, -0.02)
            hinge.scale = SCNVector3(0.97, 0.97, 0.97)
            // The same gradient image works for both wings; only the side
            // that would otherwise run tip-to-base needs its U flipped so
            // the color always reads as body-to-tip in world space.
            func gradientMaterial() -> SCNMaterial {
                let material = SCNMaterial()
                material.diffuse.contents = wingGradient
                material.lightingModel = .lambert; material.isDoubleSided = true
                if side < 0 {
                    material.diffuse.wrapS = .repeat
                    material.diffuse.contentsTransform = SCNMatrix4MakeScale(-1, 1, 1)
                }
                return material
            }
            // Paper-thin flat panels instead of solid cones/spheres, for a
            // delicate wing rather than a thick, fleshy-looking one.
            let fore = SCNPlane(width: 0.30, height: 0.34)
            fore.cornerRadius = 0.10; fore.materials = [gradientMaterial()]
            let foreNode = SCNNode(geometry: fore)
            foreNode.eulerAngles.x = -.pi / 2
            foreNode.position = SCNVector3(Float(side) * 0.15, 0.002, -0.10)
            hinge.addChildNode(foreNode)
            // A dark tip patch, a classic butterfly wing marking — another
            // thin sheet, held a hair above the forewing to avoid z-fighting.
            let tip = SCNPlane(width: 0.11, height: 0.13)
            tip.cornerRadius = 0.05; tip.materials = [edge]
            let tipNode = SCNNode(geometry: tip)
            tipNode.eulerAngles.x = -.pi / 2
            tipNode.position = SCNVector3(Float(side) * 0.23, 0.004, -0.20)
            hinge.addChildNode(tipNode)
            // Hindwing: smaller, trailing behind the forewing.
            let hind = SCNPlane(width: 0.20, height: 0.22)
            hind.cornerRadius = 0.09; hind.materials = [gradientMaterial()]
            let hindNode = SCNNode(geometry: hind)
            hindNode.eulerAngles.x = -.pi / 2
            hindNode.position = SCNVector3(Float(side) * 0.09, -0.002, 0.14)
            hinge.addChildNode(hindNode)
            root.addChildNode(hinge)
        }
        let bodyGroup = SCNNode()
        bodyGroup.scale = SCNVector3(0.96, 0.96, 0.96)
        root.addChildNode(bodyGroup)
        let body = SCNCapsule(capRadius: 0.02, height: 0.24)
        body.radialSegmentCount = 6
        body.firstMaterial?.diffuse.contents = UIColor(red: 0.88, green: 0.86, blue: 0.80, alpha: 1)
        let bodyNode = SCNNode(geometry: body)
        bodyNode.eulerAngles.x = .pi / 2
        bodyGroup.addChildNode(bodyNode)
        let head = SCNSphere(radius: 0.03); head.segmentCount = 8; head.materials = [dark]
        let headNode = SCNNode(geometry: head)
        headNode.position = SCNVector3(0, 0, -0.13)
        bodyGroup.addChildNode(headNode)
        for side in [-1.0, 1.0] {
            let antenna = SCNNode()
            antenna.position = SCNVector3(Float(side) * 0.012, 0.012, -0.145)
            antenna.eulerAngles.x = -0.55
            antenna.eulerAngles.z = Float(side) * 0.4
            let shape = SCNCylinder(radius: 0.0035, height: 0.09)
            shape.radialSegmentCount = 5; shape.materials = [dark]
            let node = SCNNode(geometry: shape)
            node.position.y = 0.045
            antenna.addChildNode(node)
            bodyGroup.addChildNode(antenna)
        }
        return root
    }

    // A small, simple low-poly bird: rounded body, a paler belly, a short
    // beak and tail, and a pair of flat wing panels that flap symmetrically.
    private static func bird(_ index: Int) -> SCNNode {
        let root = SCNNode()
        root.position = SCNVector3(cos(Double(index) * 3.6) * 6, 4.5 + Double(index % 2) * 0.8, sin(Double(index) * 3.6) * 6)
        let palettes: [(UIColor, UIColor)] = [
            (UIColor(red: 0.29, green: 0.45, blue: 0.62, alpha: 1), UIColor(red: 0.93, green: 0.78, blue: 0.55, alpha: 1)),
            (UIColor(red: 0.55, green: 0.22, blue: 0.20, alpha: 1), UIColor(red: 0.88, green: 0.86, blue: 0.80, alpha: 1))
        ]
        let (backColor, bellyColor) = palettes[index % palettes.count]
        let backMaterial = SCNMaterial(); backMaterial.diffuse.contents = backColor; backMaterial.lightingModel = .lambert
        let bellyMaterial = SCNMaterial(); bellyMaterial.diffuse.contents = bellyColor; bellyMaterial.lightingModel = .lambert
        let beakMaterial = SCNMaterial(); beakMaterial.diffuse.contents = UIColor(red: 0.95, green: 0.65, blue: 0.15, alpha: 1); beakMaterial.lightingModel = .lambert
        let darkMaterial = SCNMaterial(); darkMaterial.diffuse.contents = UIColor(red: 0.12, green: 0.11, blue: 0.10, alpha: 1); darkMaterial.lightingModel = .lambert

        let body = SCNSphere(radius: 0.11); body.segmentCount = 10; body.materials = [backMaterial]
        let bodyNode = SCNNode(geometry: body)
        bodyNode.scale = SCNVector3(0.85, 0.95, 1.35)
        root.addChildNode(bodyNode)

        let belly = SCNSphere(radius: 0.085); belly.segmentCount = 8; belly.materials = [bellyMaterial]
        let bellyNode = SCNNode(geometry: belly)
        bellyNode.scale = SCNVector3(0.8, 0.75, 1.05)
        bellyNode.position = SCNVector3(0, -0.03, 0.02)
        root.addChildNode(bellyNode)

        let head = SCNSphere(radius: 0.07); head.segmentCount = 8; head.materials = [backMaterial]
        let headNode = SCNNode(geometry: head)
        headNode.position = SCNVector3(0, 0.06, -0.14)
        root.addChildNode(headNode)

        let beak = SCNCone(topRadius: 0, bottomRadius: 0.022, height: 0.06)
        beak.radialSegmentCount = 6; beak.materials = [beakMaterial]
        let beakNode = SCNNode(geometry: beak)
        beakNode.eulerAngles.x = -.pi / 2
        beakNode.position = SCNVector3(0, 0.05, -0.205)
        root.addChildNode(beakNode)

        for side in [-1.0, 1.0] {
            let eye = SCNSphere(radius: 0.012); eye.segmentCount = 6; eye.materials = [darkMaterial]
            let eyeNode = SCNNode(geometry: eye)
            eyeNode.position = SCNVector3(Float(side) * 0.045, 0.08, -0.165)
            root.addChildNode(eyeNode)
        }

        // A small triangular tail, fanned out behind the body.
        let tail = SCNCone(topRadius: 0.001, bottomRadius: 0.07, height: 0.16)
        tail.radialSegmentCount = 3; tail.materials = [backMaterial]
        let tailNode = SCNNode(geometry: tail)
        tailNode.eulerAngles.x = .pi / 2 + 0.35
        tailNode.position = SCNVector3(0, 0.01, 0.19)
        root.addChildNode(tailNode)

        for side in [-1.0, 1.0] {
            let hinge = SCNNode()
            hinge.name = side < 0 ? "leftBirdWing" : "rightBirdWing"
            // The hinge sits right at the body's actual side (its scaled
            // radius, ~0.094), so the flap pivots at the seam instead of
            // swinging a wing whose root never touches the body.
            hinge.position = SCNVector3(Float(side) * 0.09, 0.015, 0)
            let wingMaterial = SCNMaterial()
            wingMaterial.diffuse.contents = backColor
            wingMaterial.lightingModel = .lambert
            wingMaterial.isDoubleSided = true
            // A flat panel lying in the spanwise/chordwise plane (like the
            // butterfly's wings) rather than standing up as a vertical fin —
            // that vertical orientation was the detachment bug, since a
            // fin's mesh never actually spans the gap back to the body.
            let wingSpan: CGFloat = 0.20
            let wing = SCNPlane(width: wingSpan, height: 0.11)
            wing.cornerRadius = 0.035; wing.materials = [wingMaterial]
            let wingNode = SCNNode(geometry: wing)
            wingNode.eulerAngles.x = -.pi / 2
            // Offset by half the wing's own span so its inner edge lines up
            // with the hinge origin instead of the wing's center.
            wingNode.position = SCNVector3(Float(side) * Float(wingSpan / 2), 0, 0)
            hinge.addChildNode(wingNode)
            root.addChildNode(hinge)
        }
        return root
    }
}
