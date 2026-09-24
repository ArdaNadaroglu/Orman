import SceneKit
import UIKit

/// Shared layout for planting, water geometry and animal navigation.
enum ForestTerrain {
    static let waterHalfWidth = 0.78
    static func riverX(_ z: Double) -> Double { 1.5 + 1.8 * sin(z * 0.20) + 0.45 * sin(z * 0.43) }
    static func riverClearance(_ point: SCNVector3) -> Double {
        abs(Double(point.x) - riverX(Double(point.z)))
    }

    static let bridgeCenter = 1.5
    static let bridgeHalfLength = 3.4

    static func onBridge(_ point: SCNVector3) -> Bool {
        abs(Double(point.z)) <= 0.36 && abs(Double(point.x) - bridgeCenter) <= bridgeHalfLength
    }

    static func walkable(_ point: SCNVector3) -> Bool {
        // Rails can only be entered through the two open ends.
        if abs(Double(point.x) - bridgeCenter) < bridgeHalfLength && abs(Double(point.z)) < 1.15 {
            return onBridge(point)
        }
        return riverClearance(point) >= 1.65 || onBridge(point)
    }

    static func walkingHeight(_ point: SCNVector3) -> Float {
        guard abs(Double(point.z)) <= 0.825, abs(Double(point.x) - bridgeCenter) <= bridgeHalfLength else { return 0.03 }
        let t = (Double(point.x) - bridgeCenter + bridgeHalfLength) / (2 * bridgeHalfLength)
        return Float(0.03 + 0.32 * pow(sin(t * .pi), 2))
    }

    private static func bridge() -> SCNNode {
        let root = SCNNode(); root.name = "woodenBridge"
        let wood = SCNMaterial()
        wood.diffuse.contents = UIColor(red: 0.49, green: 0.31, blue: 0.17, alpha: 1)
        let lightWood = SCNMaterial()
        lightWood.diffuse.contents = UIColor(red: 0.65, green: 0.45, blue: 0.26, alpha: 1)
        func beam(from a: SCNVector3, to b: SCNVector3, thickness: CGFloat) {
            let dx = b.x-a.x, dy = b.y-a.y, dz = b.z-a.z
            let shape = SCNBox(width: thickness, height: thickness, length: CGFloat(sqrt(dx*dx+dy*dy+dz*dz)), chamferRadius: 0.02)
            shape.materials = [wood]
            let node = SCNNode(geometry: shape)
            node.position = SCNVector3((a.x+b.x)/2, (a.y+b.y)/2, (a.z+b.z)/2)
            node.look(at: b); root.addChildNode(node)
        }
        for index in 0..<28 {
            let x = bridgeCenter - bridgeHalfLength + (Double(index)+0.5) * (bridgeHalfLength*2/28)
            let top = Double(walkingHeight(SCNVector3(x, 0, 0)))
            let plank = SCNBox(width: bridgeHalfLength*2/28-0.008, height: 0.10, length: 1.65, chamferRadius: 0.025)
            plank.materials = [index % 3 == 0 ? wood : lightWood]
            let node = SCNNode(geometry: plank)
            node.position = SCNVector3(x, top-0.025, 0)
            root.addChildNode(node)
        }
        for side in [-1.0, 1.0] {
            var previous: SCNVector3?
            for index in 0...6 {
                let x = bridgeCenter - bridgeHalfLength + Double(index) * bridgeHalfLength / 3
                let y = Double(walkingHeight(SCNVector3(x,0,0)))
                let bottom = SCNVector3(x, y-0.06, side*0.77)
                let top = SCNVector3(x, y+0.65, side*0.77)
                beam(from: bottom, to: top, thickness: 0.09)
                if let previous { beam(from: previous, to: top, thickness: 0.075) }
                previous = top
            }
        }
        return root
    }

    static func plantingPositions(count: Int) -> [SCNVector3] {
        guard count > 0 else { return [] }
        var result: [SCNVector3] = []
        var candidate = 0
        while result.count < count {
            let distance = 4 * sqrt(Double(candidate))
            let angle = Double(candidate) * 2.399963
            let point = SCNVector3(cos(angle) * distance, 0.03, sin(angle) * distance)
            if riverClearance(point) > 3.25 && !(abs(Double(point.z)) < 2.8 && abs(Double(point.x) - bridgeCenter) < 5.5) { result.append(point) }
            candidate += 1
        }
        return result
    }

    static func update(_ root: SCNNode, radius: Double, moving: Bool, sunlight: Double = 0) {
        let sun = max(0, min(1, sunlight))
        let river: SCNNode
        if let existing = root.childNode(withName: "river", recursively: false), existing.childNodes.first?.name == String(radius) {
            river = existing
        } else {
            root.childNode(withName: "river", recursively: false)?.removeFromParentNode()
            river = SCNNode(); river.name = "river"
            let bank = ribbon(radius: radius, halfWidth: 1.17, y: 0.025, color: UIColor(red: 0.66, green: 0.65, blue: 0.44, alpha: 1))
            bank.name = String(radius)
            river.addChildNode(bank)
            let shallows = ribbon(radius: radius, halfWidth: 1.14, y: 0.047, color: UIColor(red: 0.30, green: 0.57, blue: 0.49, alpha: 1))
            shallows.name = "shallows"
            river.addChildNode(shallows)
            let water = ribbon(radius: radius, halfWidth: waterHalfWidth, y: 0.052, color: UIColor(red: 0.14, green: 0.48, blue: 0.54, alpha: 1))
            water.name = "waterSurface"
            if let material = water.geometry?.firstMaterial {
                material.lightingModel = .physicallyBased
                material.roughness.contents = 0.24
                material.metalness.contents = 0
                material.normal.contents = waterTexture(normal: true)
                material.normal.intensity = 0.38
                material.normal.wrapS = .repeat; material.normal.wrapT = .repeat
                material.diffuse.contents = waterTexture(normal: false)
                material.diffuse.wrapT = .repeat
            }
            river.addChildNode(water)
            let stone = SCNMaterial()
            stone.diffuse.contents = UIColor(red: 0.63, green: 0.66, blue: 0.57, alpha: 1)
            for index in 0..<Int(radius * 1.3) {
                let z = -radius + 1 + Double(index) * 1.5
                let side = index % 2 == 0 ? -1.0 : 1.0
                let x = riverX(z) + side * (1.05 + Double(index % 3) * 0.09)
                guard hypot(x, z) < radius - 0.6, abs(z) > 1.3 else { continue }
                let shape = SCNSphere(radius: 0.12 + CGFloat(index % 3) * 0.035)
                shape.segmentCount = 7; shape.materials = [stone]
                let pebble = SCNNode(geometry: shape)
                pebble.position = SCNVector3(x, 0.07, z)
                pebble.scale = SCNVector3(1.4, 0.6, 1)
                river.addChildNode(pebble)
            }
            for index in 0..<24 {
                let glint = SCNNode(geometry: SCNCapsule(capRadius: 0.024, height: 0.32))
                glint.name = "flow\(index)"
                glint.geometry?.firstMaterial?.diffuse.contents = UIColor(red: 0.73, green: 0.92, blue: 0.91, alpha: 1)
                glint.geometry?.firstMaterial?.lightingModel = .lambert
                glint.opacity = 0.48
                glint.eulerAngles.x = .pi / 2
                placeGlint(glint, index: index, time: 0, radius: radius)
                river.addChildNode(glint)
            }
            river.addChildNode(bridge())
            root.addChildNode(river)
        }
        if let water = river.childNode(withName: "waterSurface", recursively: false) {
            if let material = water.geometry?.firstMaterial {
                // Blinn gives direct control over highlights; cloudy/night skies get none.
                material.lightingModel = sun > 0.01 ? .blinn : .lambert
                material.specular.contents = UIColor.white
                material.specular.intensity = CGFloat(sun * 0.22)
                material.shininess = 70
                material.reflective.intensity = 0
                material.normal.intensity = CGFloat(0.18 + sun * 0.12)
            }
            if moving && water.action(forKey: "surfaceFlow") == nil {
                water.runAction(.repeatForever(.customAction(duration: 24) { node, elapsed in
                    node.geometry?.firstMaterial?.normal.contentsTransform = SCNMatrix4MakeTranslation(0, Float(elapsed/24), 0)
                }), forKey: "surfaceFlow")
            } else if !moving { water.removeAction(forKey: "surfaceFlow") }
        }
        for glint in river.childNodes where glint.name?.hasPrefix("flow") == true {
            guard let index = Int(glint.name!.dropFirst(4)) else { continue }
            glint.geometry?.firstMaterial?.transparency = CGFloat(sun * 0.55)
            if moving && sun > 0.01 && glint.action(forKey: "current") == nil {
                glint.runAction(.repeatForever(.customAction(duration: 80) { node, elapsed in
                    placeGlint(node, index: index, time: Double(elapsed), radius: radius)
                }), forKey: "current")
            } else if !moving || sun <= 0.01 { glint.removeAction(forKey: "current") }
        }
    }

    private static func placeGlint(_ node: SCNNode, index: Int, time: Double, radius: Double) {
        let progress = (Double(index) / 24 + time / 80).truncatingRemainder(dividingBy: 1)
        let z = (progress * 2 - 1) * radius
        let offset = Double(index % 3 - 1) * 0.35
        let x = riverX(z) + offset
        node.position = SCNVector3(x, 0.067, z)
        node.opacity = CGFloat(0.12 + 0.16 * pow(sin(progress * .pi * 8 + Double(index)), 2))
        node.scale = SCNVector3(0.65, 0.65 + Double(index%4)*0.15, 0.35)
        node.eulerAngles.y = Float(atan2(riverX(z + 0.05) - riverX(z - 0.05), 0.1))
        node.isHidden = hypot(x, z) > radius - 0.4
    }

    // Small, seamless procedural textures are shared by the surface; no external assets.
    private static func waterTexture(normal: Bool) -> CGImage? {
        let width = 128, height = 128
        var pixels = [UInt8](repeating: 255, count: width*height*4)
        for y in 0..<height {
            for x in 0..<width {
                let u = Double(x)/Double(width), v = Double(y)/Double(height)
                let a = 2 * Double.pi * (u*3 + v*4)
                let b = 2 * Double.pi * (u*5 - v*2)
                let offset = (y*width+x)*4
                let values: [Double]
                if normal {
                    let dx = 0.16*cos(a) + 0.07*cos(b)
                    let dy = 0.12*cos(a) - 0.05*cos(b)
                    let length = sqrt(dx*dx+dy*dy+1)
                    values = [0.5+dx/length*0.5, 0.5+dy/length*0.5, 0.5+0.5/length]
                } else {
                    let edge = pow(abs(u*2-1), 2)
                    let light = 0.009*sin(a)*sin(b) + 0.004*cos(2 * .pi * (u + v*3))
                    values = [0.17+edge*0.12+light, 0.40+edge*0.12+light, 0.43+edge*0.05+light]
                }
                for c in 0..<3 { pixels[offset+c] = UInt8(max(0,min(255,values[c]*255))) }
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width*4,
                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    private static func ribbon(radius: Double, halfWidth: Double, y: Double, color: UIColor) -> SCNNode {
        let steps = max(100, Int(radius * 10))
        var vertices: [SCNVector3] = []
        var coordinates: [CGPoint] = []
        var indices: [Int32] = []
        for index in 0...steps {
            let z = -radius + Double(index) / Double(steps) * radius * 2
            let edge = sqrt(max(0, radius * radius - z * z))
            let left = max(-edge, min(edge, riverX(z) - halfWidth))
            let right = max(-edge, min(edge, riverX(z) + halfWidth))
            vertices.append(SCNVector3(left, y, z)); vertices.append(SCNVector3(right, y, z))
            coordinates.append(CGPoint(x: 0, y: z/3)); coordinates.append(CGPoint(x: 1, y: z/3))
            if index < steps {
                let a = Int32(index * 2)
                indices += [a, a + 2, a + 1, a + 1, a + 2, a + 3]
            }
        }
        let normals = Array(repeating: SCNVector3(0, 1, 0), count: vertices.count)
        let geometry = SCNGeometry(sources: [.init(vertices: vertices), .init(normals: normals), .init(textureCoordinates: coordinates)], elements: [.init(indices: indices, primitiveType: .triangles)])
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.lightingModel = .lambert
        material.isDoubleSided = true
        geometry.materials = [material]
        return SCNNode(geometry: geometry)
    }
}
