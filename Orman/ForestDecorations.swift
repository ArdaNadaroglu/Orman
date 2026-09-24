import SceneKit
import UIKit

// A cosmetic object that can be placed in the forest — earned for free by
// keeping a long enough streak, or unlocked right away with a one-time
// purchase. Exactly one exists today (the wishing fountain); the catalog is
// a list so more can be added later without touching the store UI or the
// placement logic in ContentView.
struct ForestDecoration: Identifiable, Equatable {
    let id: String
    let icon: String
    let streakReward: Int?
    let productID: String
    let priceFallback: String
    let priceAmount: Decimal

    var name: String {
        switch id {
        case "wishingFountain": return T("Dilek Çeşmesi", "Wishing Fountain", "Wunschbrunnen")
        case "forestBell": return T("Orman Çanı", "Forest Bell", "Waldglocke")
        case "forestSwing": return T("Orman Salıncağı", "Forest Swing", "Waldschaukel")
        case "waterMill": return T("Su Değirmeni", "Watermill", "Wassermühle")
        default: return id
        }
    }
    var about: String {
        switch id {
        case "forestSwing":
            return T("Çiçekler arasında yavaşça sallanan, halatlı ve ahşap oturaklı bir orman salıncağı.", "A gently swaying wooden swing nestled among flowers.", "Eine sanft schwingende Holzschaukel zwischen Blumen.")
        case "wishingFountain":
            return T("Ormanına ışıltılı, akan sulu bir çeşme kur.", "Add a glittering, flowing fountain to your forest.", "Stelle einen glitzernden, plätschernden Brunnen in deinen Wald.")
        case "waterMill":
            return T("Dere kenarında dönen ahşap çark, taş duvarlar ve sıcak pencereleriyle yaşayan bir su değirmeni.", "A riverside watermill with a turning wooden wheel, stone walls and warm windows.", "Eine Wassermühle mit drehendem Holzrad, Steinmauern und warmen Fenstern.")
        case "forestBell":
            return T("Ormanına küçük, bronz çanlı bir ahşap çan kulesi ekle.", "Add a small wooden bell tower with a bronze bell to your forest.", "Füge deinem Wald einen kleinen Glockenturm mit einer Bronzeglocke hinzu.")
        default: return ""
        }
    }
    var streakHint: String {
        guard let streakReward else { return T("Mağazaya özel dekorasyon", "Shop-exclusive decoration", "Exklusive Shop-Dekoration") }
        return T("\(streakReward) günlük seriyle ücretsiz kazanılır", "Earned free with a \(streakReward)-day streak", "Kostenlos ab einer \(streakReward)-Tage-Serie")
    }
}

enum ForestDecorCatalog {
    static let wishingFountain = ForestDecoration(
        id: "wishingFountain",
        icon: "drop.circle.fill",
        streakReward: 14,
        productID: "com.arda.orman.decor.fountain",
        priceFallback: "₺75,00", priceAmount: 75
    )
    static let forestBell = ForestDecoration(
        id: "forestBell",
        icon: "bell.circle.fill",
        streakReward: 30,
        productID: "com.arda.orman.decor.bell",
        priceFallback: "₺60,00", priceAmount: 60
    )
    static let waterMill = ForestDecoration(id: "waterMill", icon: "gearshape.2.fill", streakReward: nil,
                                            productID: "com.arda.orman.decor.watermill", priceFallback: "₺99,99", priceAmount: Decimal(9999) / 100)
    static let forestSwing = ForestDecoration(id: "forestSwing", icon: "sun.max.fill", streakReward: nil,
        productID: "com.arda.orman.decor.swing", priceFallback: "₺60,00", priceAmount: 60)
    static let all: [ForestDecoration] = [forestBell, forestSwing, wishingFountain, waterMill]
}

enum ForestDecorAssets {
    // Builds the 3D node for a given decoration id, or nil if unknown.
    static func node(for id: String) -> SCNNode? {
        switch id {
        case "wishingFountain": return wishingFountain()
        case "forestBell": return forestBell()
        case "waterMill": return WaterMillAsset.make()
        case "forestSwing": return ForestSwingAsset.make()
        default: return nil
        }
    }

    // A tiered stone fountain: a wide basin holding glowing water, a
    // slender pedestal rising to a small overflow bowl that trickles back
    // down, ringed by a handful of smooth creek stones and a drift of warm
    // sparkles — the forest's one hand-crafted "premium" reward object.
    private static func wishingFountain() -> SCNNode {
        let root = SCNNode()
        root.name = "wishingFountain"

        let stone = UIColor(red: 0.64, green: 0.62, blue: 0.58, alpha: 1)
        let stoneDark = UIColor(red: 0.44, green: 0.43, blue: 0.40, alpha: 1)
        let water = UIColor(red: 0.36, green: 0.78, blue: 0.85, alpha: 1)
        let waterGlow = UIColor(red: 0.28, green: 0.62, blue: 0.72, alpha: 1)

        @discardableResult
        func solid(_ geometry: SCNGeometry, _ color: UIColor, roughness: CGFloat = 0.85) -> SCNMaterial {
            let m = SCNMaterial()
            m.diffuse.contents = color
            m.lightingModel = .physicallyBased
            m.roughness.contents = roughness
            geometry.materials = [m]
            return m
        }
        @discardableResult
        func place(_ geometry: SCNGeometry, _ x: Float, _ y: Float, _ z: Float) -> SCNNode {
            let node = SCNNode(geometry: geometry)
            node.position = SCNVector3(x, y, z)
            root.addChildNode(node)
            return node
        }
        @discardableResult
        func glow(_ geometry: SCNGeometry, _ color: UIColor, _ emission: UIColor) -> SCNMaterial {
            let m = SCNMaterial()
            m.diffuse.contents = color
            m.emission.contents = emission
            m.lightingModel = .constant
            m.isDoubleSided = true
            geometry.materials = [m]
            return m
        }

        // Two-step stone foundation the basin sits on.
        let footing = SCNCylinder(radius: 1.55, height: 0.2)
        footing.radialSegmentCount = 28
        solid(footing, stoneDark)
        place(footing, 0, 0.1, 0)

        let base = SCNCylinder(radius: 1.28, height: 0.22)
        base.radialSegmentCount = 28
        solid(base, stone)
        place(base, 0, 0.31, 0)

        // Basin rim, standing proud of the water so it reads as a real bowl.
        let rim = SCNTorus(ringRadius: 1.05, pipeRadius: 0.13)
        rim.ringSegmentCount = 32
        rim.pipeSegmentCount = 16
        solid(rim, stone)
        place(rim, 0, 0.5, 0)

        // Glowing basin water, sitting a touch below the rim.
        let basinWater = SCNCylinder(radius: 0.98, height: 0.05)
        basinWater.radialSegmentCount = 32
        let basinMat = glow(basinWater, water, waterGlow)
        basinMat.transparency = 0.92
        place(basinWater, 0, 0.47, 0)

        // Slender central pedestal.
        let pedestal = SCNCone(topRadius: 0.13, bottomRadius: 0.2, height: 1.0)
        pedestal.radialSegmentCount = 20
        solid(pedestal, stone)
        place(pedestal, 0, 1.0, 0)

        // Small overflow bowl at the top the water spills from.
        let bowlRim = SCNCylinder(radius: 0.32, height: 0.1)
        bowlRim.radialSegmentCount = 24
        solid(bowlRim, stoneDark)
        place(bowlRim, 0, 1.52, 0)

        let bowlWater = SCNCylinder(radius: 0.26, height: 0.05)
        bowlWater.radialSegmentCount = 24
        glow(bowlWater, water, waterGlow)
        place(bowlWater, 0, 1.58, 0)

        // A handful of smooth creek stones tucked around the base.
        for (dx, dz, r) in [(1.45, 0.55, 0.15), (-1.35, -0.7, 0.12), (0.55, -1.45, 0.1), (-0.6, 1.4, 0.13)] {
            let pebble = SCNSphere(radius: CGFloat(r))
            pebble.segmentCount = 10
            solid(pebble, stoneDark, roughness: 0.9)
            place(pebble, Float(dx), Float(r * 0.8), Float(dz))
        }

        // The actual flowing water: it overflows the small bowl's rim as a
        // full ring and falls straight down, just outside the pedestal —
        // never through its solid interior, which is what left the water
        // invisible, hidden inside the stone, in an earlier version of this.
        let waterfall = SCNParticleSystem()
        waterfall.birthRate = 220
        waterfall.particleLifeSpan = 0.62
        waterfall.particleLifeSpanVariation = 0.06
        waterfall.particleSize = 0.028
        waterfall.particleSizeVariation = 0.008
        waterfall.stretchFactor = 0.4
        waterfall.particleColor = UIColor(red: 0.64, green: 0.91, blue: 0.97, alpha: 0.9)
        waterfall.particleColorVariation = SCNVector4(0, 0, 0.05, 0.1)
        waterfall.emitterShape = SCNTorus(ringRadius: 0.3, pipeRadius: 0.025)
        waterfall.birthLocation = .surface
        waterfall.particleVelocity = 0.12
        waterfall.particleVelocityVariation = 0.03
        waterfall.acceleration = SCNVector3(0, -2.8, 0)
        waterfall.spreadingAngle = 2
        waterfall.blendMode = .additive
        waterfall.isLightingEnabled = false
        let waterfallNode = SCNNode()
        waterfallNode.position = SCNVector3(0, 1.5, 0)
        waterfallNode.addParticleSystem(waterfall)
        root.addChildNode(waterfallNode)

        // A ring of spray exactly where that curtain of water meets the
        // basin surface below.
        let splash = SCNParticleSystem()
        splash.birthRate = 90
        splash.particleLifeSpan = 0.3
        splash.particleLifeSpanVariation = 0.08
        splash.particleSize = 0.022
        splash.particleSizeVariation = 0.008
        splash.particleColor = UIColor(red: 0.75, green: 0.94, blue: 0.98, alpha: 0.85)
        splash.emitterShape = SCNTorus(ringRadius: 0.3, pipeRadius: 0.03)
        splash.birthLocation = .surface
        splash.particleVelocity = 0.35
        splash.particleVelocityVariation = 0.15
        splash.spreadingAngle = 60
        splash.acceleration = SCNVector3(0, -1.3, 0)
        splash.blendMode = .additive
        splash.isLightingEnabled = false
        let splashNode = SCNNode()
        splashNode.position = SCNVector3(0, 0.51, 0)
        splashNode.addParticleSystem(splash)
        root.addChildNode(splashNode)

        // A slow drift of warm sparkles above the whole fountain — the bit
        // that reads as "magical reward" rather than plain garden decor.
        let sparkle = SCNParticleSystem()
        sparkle.birthRate = 5
        sparkle.particleLifeSpan = 3.2
        sparkle.particleLifeSpanVariation = 1.1
        sparkle.particleSize = 0.05
        sparkle.particleSizeVariation = 0.02
        sparkle.particleColor = UIColor(red: 1, green: 0.92, blue: 0.66, alpha: 0.85)
        sparkle.emitterShape = SCNCylinder(radius: 1.1, height: 0.4)
        sparkle.birthLocation = .volume
        sparkle.particleVelocity = 0.12
        sparkle.particleVelocityVariation = 0.06
        sparkle.acceleration = SCNVector3(0, 0.1, 0)
        sparkle.blendMode = .additive
        sparkle.isLightingEnabled = false
        let sparkleNode = SCNNode()
        sparkleNode.position = SCNVector3(0, 0.7, 0)
        sparkleNode.addParticleSystem(sparkle)
        root.addChildNode(sparkleNode)

        // A soft cyan glow so it still reads as the forest's little lit
        // landmark after dark, echoing the lamp post across the way.
        let light = SCNNode()
        light.light = SCNLight()
        light.light?.type = .omni
        light.light?.color = UIColor(red: 0.55, green: 0.85, blue: 0.95, alpha: 1)
        light.light?.intensity = 110
        light.light?.attenuationStartDistance = 0.5
        light.light?.attenuationEndDistance = 4
        light.light?.castsShadow = false
        light.position = SCNVector3(0, 0.9, 0)
        root.addChildNode(light)

        return root
    }

    // A small hand-built belfry: four tapered, braced wooden posts holding
    // up a two-tier roof with a finial, a properly flared bronze bell and
    // its clapper hanging underneath, moss at the foot, and a little
    // flowerbed scattered in the grass around it. The 30-day-streak
    // reward, one tier above the fountain.
    private static func forestBell() -> SCNNode {
        let root = SCNNode()
        root.name = "forestBell"

        let wood = UIColor(red: 0.38, green: 0.25, blue: 0.16, alpha: 1)
        let woodDark = UIColor(red: 0.24, green: 0.16, blue: 0.11, alpha: 1)
        let roofColor = UIColor(red: 0.20, green: 0.36, blue: 0.32, alpha: 1)
        let bronze = UIColor(red: 0.74, green: 0.54, blue: 0.25, alpha: 1)
        let bronzeDark = UIColor(red: 0.52, green: 0.37, blue: 0.18, alpha: 1)
        let stone = UIColor(red: 0.52, green: 0.5, blue: 0.47, alpha: 1)
        let moss = UIColor(red: 0.42, green: 0.56, blue: 0.28, alpha: 1)

        @discardableResult
        func solid(_ geometry: SCNGeometry, _ color: UIColor, roughness: CGFloat = 0.85, metalness: CGFloat = 0) -> SCNMaterial {
            let m = SCNMaterial()
            m.diffuse.contents = color
            m.lightingModel = .physicallyBased
            m.roughness.contents = roughness
            m.metalness.contents = metalness
            geometry.materials = [m]
            return m
        }
        @discardableResult
        func place(_ geometry: SCNGeometry, _ x: Float, _ y: Float, _ z: Float) -> SCNNode {
            let node = SCNNode(geometry: geometry)
            node.position = SCNVector3(x, y, z)
            root.addChildNode(node)
            return node
        }
        // A tapered strut between two arbitrary points, for the posts'
        // corner bracing — the same technique used for the willow's
        // drooping branches elsewhere in the forest.
        @discardableResult
        func beam(from a: SCNVector3, to b: SCNVector3, width: CGFloat, material: UIColor, roughness: CGFloat = 0.85) -> SCNNode {
            let dx = b.x - a.x, dy = b.y - a.y, dz = b.z - a.z
            let shape = SCNCone(topRadius: width * 0.8, bottomRadius: width, height: max(0.001, CGFloat(sqrt(Double(dx * dx + dy * dy + dz * dz)))))
            shape.radialSegmentCount = 8
            solid(shape, material, roughness: roughness)
            let pivot = SCNNode()
            pivot.position = SCNVector3((a.x + b.x) / 2, (a.y + b.y) / 2, (a.z + b.z) / 2)
            pivot.look(at: b)
            let node = SCNNode(geometry: shape)
            node.eulerAngles.x = .pi / 2
            pivot.addChildNode(node)
            root.addChildNode(pivot)
            return pivot
        }

        // Two-tier stone footing so it reads as properly built, matching
        // the fountain and lamp post.
        let footingLow = SCNCylinder(radius: 0.36, height: 0.1)
        footingLow.radialSegmentCount = 24
        solid(footingLow, stone, roughness: 0.9)
        place(footingLow, 0, 0.05, 0)
        let footingHigh = SCNCylinder(radius: 0.3, height: 0.08)
        footingHigh.radialSegmentCount = 24
        solid(footingHigh, UIColor(red: 0.58, green: 0.56, blue: 0.53, alpha: 1), roughness: 0.85)
        place(footingHigh, 0, 0.14, 0)

        // Four corner posts, gently tapered and leaning inward for a
        // hand-built look rather than a perfectly square kit.
        let postHeight: Float = 1.5
        let postBase: Float = 0.24
        var postTops: [SCNVector3] = []
        var postBottoms: [SCNVector3] = []
        for (dx, dz) in [(postBase, postBase), (-postBase, postBase), (-postBase, -postBase), (postBase, -postBase)] {
            let leanX = dx * 0.12, leanZ = dz * 0.12
            let bottom = SCNVector3(dx, 0.18, dz)
            let top = SCNVector3(dx - leanX, 0.18 + postHeight, dz - leanZ)
            postBottoms.append(bottom)
            postTops.append(top)
            beam(from: bottom, to: top, width: 0.03, material: wood, roughness: 0.88)
        }

        // Diagonal corner bracing on all four faces, plus a horizontal
        // ring tying the post tops together — real joinery instead of two
        // plain crossbeams.
        for i in 0..<4 {
            let next = (i + 1) % 4
            let a = postTops[i], b = postTops[next]
            beam(from: a, to: b, width: 0.024, material: woodDark)
            // Short knee braces leave the bell visible through each open face.
            for (origin, destination) in [(a,b),(b,a)] {
                let low = SCNVector3(origin.x, origin.y-0.22, origin.z)
                let inset = SCNVector3(origin.x+(destination.x-origin.x)*0.32, origin.y, origin.z+(destination.z-origin.z)*0.32)
                beam(from: low, to: inset, width: 0.016, material: wood)
            }
            let shoe = SCNCylinder(radius: 0.039, height: 0.075)
            shoe.radialSegmentCount = 12
            solid(shoe, bronzeDark, roughness: 0.65, metalness: 0.45)
            place(shoe, postBottoms[i].x, 0.215, postBottoms[i].z)
        }
        // A visible wooden yoke connects the hanging loop to the tower.
        beam(from: SCNVector3(-0.21,1.61,0), to: SCNVector3(0.21,1.61,0), width: 0.035, material: woodDark)

        // A two-tier peaked roof with wide eaves, plus a slender finial.
        let eaves = SCNCone(topRadius: 0.3, bottomRadius: 0.46, height: 0.16)
        eaves.radialSegmentCount = 4
        solid(eaves, roofColor, roughness: 0.66, metalness: 0.25)
        place(eaves, 0, postHeight + 0.26, 0)
        let cap = SCNCone(topRadius: 0.015, bottomRadius: 0.26, height: 0.3)
        cap.radialSegmentCount = 4
        solid(cap, roofColor, roughness: 0.60, metalness: 0.3)
        place(cap, 0, postHeight + 0.48, 0)
        let finial = SCNSphere(radius: 0.028)
        finial.segmentCount = 10
        solid(finial, bronze, roughness: 0.35, metalness: 0.7)
        place(finial, 0, postHeight + 0.65, 0)

        // A continuous turned profile, including the inside wall and rounded lip.
        // The opening remains genuinely hollow so the clapper can be seen beneath it.
        let profile: [(radius: Float, y: Float)] = [
            (0.160,-0.115),(0.163,-0.100),(0.145,-0.080),(0.120,-0.025),
            (0.096,0.055),(0.085,0.095),(0.065,0.125),(0.027,0.143),
            (0.018,0.125),(0.055,0.107),(0.071,0.082),(0.082,0.046),
            (0.106,-0.033),(0.131,-0.087),(0.144,-0.103),(0.145,-0.115)
        ]
        let segments = 48
        var vertices: [SCNVector3] = [], normals: [SCNVector3] = []
        var indices: [Int32] = []
        for i in profile.indices {
            let previous = profile[(i+profile.count-1)%profile.count]
            let next = profile[(i+1)%profile.count]
            let dr = next.radius-previous.radius, dy = next.y-previous.y
            let length = max(0.001,sqrt(dr*dr+dy*dy))
            for j in 0...segments {
                let angle = Float(j)*2 * .pi/Float(segments)
                vertices.append(SCNVector3(profile[i].radius*cos(angle),profile[i].y,profile[i].radius*sin(angle)))
                normals.append(SCNVector3(dy*cos(angle)/length,-dr/length,dy*sin(angle)/length))
                if j < segments {
                    let a = Int32(i*(segments+1)+j)
                    let b = Int32(((i+1)%profile.count)*(segments+1)+j)
                    indices += [a,b,a+1,a+1,b,b+1]
                }
            }
        }
        let shell = SCNGeometry(sources: [.init(vertices: vertices),.init(normals: normals)], elements: [.init(indices: indices,primitiveType: .triangles)])
        solid(shell, bronze, roughness: 0.32, metalness: 0.72)
        shell.firstMaterial?.isDoubleSided = true
        place(shell,0,postHeight-0.125,0).name = "bellShell"
        for (radius, y) in [(0.095,1.43),(0.128,1.33)] {
            let band = SCNTorus(ringRadius: radius, pipeRadius: 0.004)
            band.ringSegmentCount = 40; band.pipeSegmentCount = 6
            solid(band, bronzeDark, roughness: 0.44, metalness: 0.65)
            place(band,0,Float(y),0)
        }
        let lip = SCNTorus(ringRadius: 0.155, pipeRadius: 0.016)
        lip.ringSegmentCount = 24
        lip.pipeSegmentCount = 10
        solid(lip, bronzeDark, roughness: 0.3, metalness: 0.8)
        place(lip, 0, postHeight - 0.24, 0)
        let loop = SCNTorus(ringRadius: 0.03, pipeRadius: 0.009)
        loop.ringSegmentCount = 14
        solid(loop, bronzeDark, roughness: 0.3, metalness: 0.8)
        place(loop, 0, postHeight + 0.04, 0).eulerAngles.x = .pi / 2

        // The clapper hanging inside on its rod.
        let rod = SCNCylinder(radius: 0.008, height: 0.16)
        solid(rod, UIColor(red: 0.3, green: 0.28, blue: 0.25, alpha: 1), roughness: 0.5, metalness: 0.5)
        place(rod, 0, postHeight - 0.16, 0)
        let clapper = SCNSphere(radius: 0.032)
        clapper.segmentCount = 10
        solid(clapper, woodDark, roughness: 0.6)
        place(clapper, 0, postHeight - 0.25, 0)

        let corners = [SCNVector3(0.46,1.68,0), SCNVector3(0,1.68,0.46), SCNVector3(-0.46,1.68,0), SCNVector3(0,1.68,-0.46)]
        for i in corners.indices {
            beam(from: corners[i], to: corners[(i+1)%4], width: 0.012, material: bronzeDark, roughness: 0.6)
            let corner = corners[i]
            beam(from: SCNVector3(0,2.13,0), to: SCNVector3(corner.x*0.56,1.83,corner.z*0.56), width: 0.008, material: bronzeDark, roughness: 0.6)
        }
        // A hanging pull cord and small wooden grip add a recognisable bell detail.
        beam(from: SCNVector3(0,1.25,0),to: SCNVector3(0.035,0.69,0.025),width: 0.006,material: UIColor(red:0.66,green:0.56,blue:0.39,alpha:1))
        let grip = SCNCapsule(capRadius: 0.015, height: 0.09)
        solid(grip,woodDark)
        place(grip,0.035,0.66,0.025)

        // A couple of moss tufts at the base for a lived-in feel.
        for (dx, dz, s) in [(0.24, -0.2, 0.09), (-0.22, 0.17, 0.07)] {
            let tuft = SCNSphere(radius: CGFloat(s))
            tuft.segmentCount = 8
            solid(tuft, moss, roughness: 1)
            place(tuft, Float(dx), Float(s) * 0.6, Float(dz)).scale = SCNVector3(1, 0.5, 1)
        }

        // Four reusable flower meshes keep a richer bed inexpensive to render.
        let palette: [UIColor] = [
            UIColor(red: 0.99, green: 0.96, blue: 0.87, alpha: 1),
            UIColor(red: 0.91, green: 0.44, blue: 0.61, alpha: 1),
            UIColor(red: 0.63, green: 0.52, blue: 0.84, alpha: 1),
            UIColor(red: 0.98, green: 0.69, blue: 0.32, alpha: 1)
        ]
        let leafColor = UIColor(red: 0.27, green: 0.43, blue: 0.23, alpha: 1)
        func flower(_ variety: Int) -> SCNNode {
            let flower = SCNNode()
            @discardableResult
            func ellipsoid(_ position: SCNVector3, _ scale: SCNVector3, _ color: UIColor) -> SCNNode {
                let shape = SCNSphere(radius: 1); shape.segmentCount = 12
                solid(shape, color, roughness: 0.82)
                let node = SCNNode(geometry: shape); node.position = position; node.scale = scale
                flower.addChildNode(node); return node
            }
            let height = Float(0.13 + Double(variety)*0.018)
            let stem = SCNCylinder(radius: 0.0045, height: CGFloat(height))
            stem.radialSegmentCount = 7
            solid(stem, leafColor)
            let stalk = SCNNode(geometry: stem); stalk.position.y = height/2
            flower.addChildNode(stalk)
            for side: Float in [-1,1] {
                let leaf = ellipsoid(SCNVector3(side*0.022,height*(side<0 ? 0.38 : 0.60),0), SCNVector3(0.033,0.004,0.012), leafColor)
                leaf.eulerAngles.z = side*0.48
                leaf.eulerAngles.y = side*0.45
            }
            ellipsoid(SCNVector3(0,height-0.009,0), SCNVector3(0.021,0.012,0.021), leafColor)
            let petals = variety == 2 ? 6 : 9
            for i in 0..<petals {
                let angle = Float(i)*2 * .pi/Float(petals)
                let petal = ellipsoid(SCNVector3(cos(angle)*0.032,height,sin(angle)*0.032), SCNVector3(0.035,0.008, variety == 2 ? 0.022 : 0.014), palette[variety])
                petal.eulerAngles.y = -angle
                petal.eulerAngles.z = 0.18
            }
            if variety == 1 {
                let palePink = UIColor(red:0.98,green:0.68,blue:0.75,alpha:1)
                for i in 0..<6 {
                    let angle = Float(i)*2 * .pi/6+0.2
                    let inner = ellipsoid(SCNVector3(cos(angle)*0.019,height+0.009,sin(angle)*0.019), SCNVector3(0.022,0.007,0.012), palePink)
                    inner.eulerAngles.y = -angle
                }
            }
            let center = UIColor(red:0.93,green:0.65,blue:0.17,alpha:1)
            ellipsoid(SCNVector3(0,height+0.009,0),SCNVector3(0.018,0.013,0.018),center)
            for i in 0..<5 {
                let angle = Float(i)*2 * .pi/5
                ellipsoid(SCNVector3(cos(angle)*0.010,height+0.020,sin(angle)*0.010),SCNVector3(0.003,0.003,0.003),UIColor(red:1,green:0.86,blue:0.42,alpha:1))
            }
            return flower
        }
        let templates = (0..<4).map(flower)
        let flowerbed = SCNNode(); flowerbed.name = "bellFlowerbed"
        for i in 0..<30 {
            let angle = Double(i)*2.399963
            let radius = 0.46 + 0.27*sqrt(Double(i)/29)
            let node = templates[i%4].clone()
            node.name = "bellFlower\(i)"
            node.position = SCNVector3(cos(angle)*radius,0.025,sin(angle)*radius)
            let size = Float(0.88+Double(i%5)*0.065)
            node.scale = SCNVector3(size,size,size)
            node.eulerAngles = SCNVector3(0,Float(angle+0.4),Float(sin(Double(i)*1.7)*0.10))
            flowerbed.addChildNode(node)
        }
        root.addChildNode(flowerbed)

        return root
    }
}

/// A compact mill whose wheel sits in the stream while the house stays on the bank.
enum WaterMillAsset {
    static func make() -> SCNNode {
        let root = SCNNode(); root.name = "waterMill"
        root.scale = SCNVector3(1.1, 1.1, 1.1)
        func material(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, rough: CGFloat = 0.85, metal: CGFloat = 0) -> SCNMaterial {
            let m = SCNMaterial(); m.diffuse.contents = UIColor(red:r,green:g,blue:b,alpha:1)
            m.lightingModel = .physicallyBased; m.roughness.contents = rough; m.metalness.contents = metal
            return m
        }
        let timber = material(0.35,0.23,0.14), darkWood = material(0.19,0.13,0.09)
        let planks = (0..<4).map { i in material(0.48+CGFloat(i)*0.023,0.34+CGFloat(i)*0.018,0.22+CGFloat(i)*0.012) }
        let rocks = (0..<4).map { i in material(0.44+CGFloat(i)*0.03,0.45+CGFloat(i)*0.028,0.40+CGFloat(i)*0.025) }
        let tiles = (0..<4).map { i in material(0.35+CGFloat(i)*0.027,0.20+CGFloat(i)*0.016,0.15+CGFloat(i)*0.012) }
        let iron = material(0.13,0.16,0.15,rough:0.46,metal:0.65)
        let glass = material(0.70,0.47,0.20,rough:0.4)
        glass.emission.contents = UIColor(red:1,green:0.58,blue:0.20,alpha:1)
        glass.emission.intensity = 0.12
        @discardableResult
        func add(_ geometry: SCNGeometry, _ position: SCNVector3, _ m: SCNMaterial, parent: SCNNode? = nil) -> SCNNode {
            geometry.materials = [m]; let node = SCNNode(geometry:geometry); node.position = position
            (parent ?? root).addChildNode(node); return node
        }
        @discardableResult
        func box(_ w: CGFloat,_ h: CGFloat,_ d: CGFloat,_ x: Float,_ y: Float,_ z: Float,_ m: SCNMaterial,parent: SCNNode? = nil) -> SCNNode {
            add(SCNBox(width:w,height:h,length:d,chamferRadius:min(0.012,min(w,min(h,d))*0.15)),SCNVector3(x,y,z),m,parent:parent)
        }
        func beam(_ a: SCNVector3,_ b: SCNVector3,_ width: CGFloat,_ m: SCNMaterial,parent: SCNNode? = nil) {
            let dx=b.x-a.x,dy=b.y-a.y,dz=b.z-a.z
            let node=box(width,width,CGFloat(sqrt(dx*dx+dy*dy+dz*dz)),(a.x+b.x)/2,(a.y+b.y)/2,(a.z+b.z)/2,m,parent:parent)
            node.look(at: (parent ?? root).convertPosition(b, to: nil))
        }
        // Dressed stone foundation, staggered courses and corner timber joinery.
        box(1.32,0.12,1.53,0.48,0.07,0,rocks[1])
        box(1.18,0.51,1.34,0.48,0.37,0,rocks[0])
        for row in 0..<3 {
            for i in 0..<6 {
                let x = Float(-0.07+Double(i)*0.22)
                for side: Float in [-1,1] {
                    box(0.20,0.135,0.052,x,0.19+Float(row)*0.15,side*0.681,rocks[(i+row)%4])
                }
            }
            for i in 0..<6 {
                for side: Float in [-1,1] {
                    box(0.055,0.135,0.20,0.48+side*0.605,0.19+Float(row)*0.15,Float(-0.55+Double(i)*0.22),rocks[(i+row+1)%4])
                }
            }
        }
        box(1.18,0.87,1.34,0.48,1.04,0,planks[1])
        for row in 0..<9 {
            let y=Float(0.65+Double(row)*0.087)
            box(1.19,0.068,0.022,0.48,y,0.68,planks[row%4])
            box(1.19,0.068,0.022,0.48,y,-0.68,planks[(row+1)%4])
            for side: Float in [-1,1] { box(0.022,0.068,1.34,0.48+side*0.605,y,0,planks[(row+2)%4]) }
        }
        for x: Float in [-0.12,1.08] {
            for z: Float in [-0.69,0.69] { box(0.075,1.02,0.075,x,1.00,z,timber) }
        }
        for z: Float in [-0.70,0.70] {
            box(1.28,0.08,0.08,0.48,0.62,z,darkWood)
            box(1.28,0.09,0.08,0.48,1.46,z,darkWood)
        }
        // A boarded front door, iron straps and a little stone threshold.
        box(0.34,0.62,0.05,0.36,0.91,0.712,darkWood)
        for i in 0..<4 { box(0.071,0.57,0.035,0.24+Float(i)*0.08,0.92,0.75,planks[i]) }
        for y: Float in [0.75,1.06] { box(0.30,0.025,0.018,0.36,y,0.777,iron) }
        let handle=SCNTorus(ringRadius:0.018,pipeRadius:0.004);handle.ringSegmentCount=12;handle.pipeSegmentCount=6
        add(handle,SCNVector3(0.47,0.94,0.79),iron).eulerAngles.x = .pi/2
        box(0.48,0.09,0.24,0.36,0.56,0.80,rocks[2])
        // Glazed windows with deep reveals, crossbars, sills and folded shutters.
        for (x,z) in [(Float(0.85),Float(0.724)),(Float(0.30),Float(-0.724))] {
            let direction: Float = z>0 ? 1 : -1
            box(0.31,0.36,0.045,x,1.13,z,darkWood)
            let pane=box(0.25,0.29,0.018,x,1.13,z+direction*0.028,glass); pane.name="millWindow"
            box(0.027,0.30,0.025,x,1.13,z+direction*0.045,timber)
            box(0.26,0.025,0.025,x,1.13,z+direction*0.045,timber)
            box(0.38,0.04,0.11,x,0.94,z,planks[2])
            for side: Float in [-1,1] {
                box(0.08,0.34,0.035,x+side*0.205,1.13,z,planks[0]).eulerAngles.y = side*0.3
            }
        }
        // Closed triangular gables, then individually overlapping roof tiles.
        for z: Float in [-0.68,0.68] {
            let v=[SCNVector3(-0.12,1.48,z),SCNVector3(1.08,1.48,z),SCNVector3(0.48,1.99,z)]
            let mesh=SCNGeometry(sources:[.init(vertices:v)],elements:[.init(indices:[Int32(0),1,2],primitiveType:.triangles)])
            mesh.materials=[planks[0]];mesh.firstMaterial?.isDoubleSided=true;root.addChildNode(SCNNode(geometry:mesh))
            beam(v[0],v[2],0.065,darkWood);beam(v[1],v[2],0.065,darkWood)
        }
        let pitch=Float(atan2(0.56,0.77))
        for side: Float in [-1,1] {
            let panel=box(0.98,0.07,1.64,0.48+side*0.39,1.72,0,tiles[0]);panel.eulerAngles.z = -side*pitch
            for row in 0..<4 {
                let t=Float(row)*0.205+0.12
                for col in 0..<8 {
                    let tile=box(0.26,0.035,0.197,0.48+side*t,2.025-t*tan(pitch),Float(col)*0.20-0.70,tiles[(row+col)%4])
                    tile.eulerAngles.z = -side*pitch
                }
            }
        }
        beam(SCNVector3(0.48,2.04,-0.84),SCNVector3(0.48,2.04,0.84),0.075,tiles[2])
        box(0.20,0.50,0.23,0.85,1.96,-0.32,rocks[0])
        box(0.26,0.06,0.29,0.85,2.23,-0.32,rocks[2])
        box(0.13,0.012,0.16,0.85,2.266,-0.32,iron)
        // Vertical wheel: two rims, radial spokes, iron ties, scooped paddles and axle.
        let wheel=SCNNode();wheel.name="millWheel";wheel.position=SCNVector3(-0.97,0.72,0)
        root.addChildNode(wheel)
        for x: Float in [-0.16,0.16] {
            for radius: CGFloat in [0.60,0.46] {
                let ring=SCNTorus(ringRadius:radius,pipeRadius:radius>0.5 ? 0.035 : 0.023)
                ring.ringSegmentCount=48;ring.pipeSegmentCount=8
                add(ring,SCNVector3(x,0,0),timber,parent:wheel).eulerAngles.z = .pi/2
            }
            for spoke in 0..<10 {
                let a=Float(spoke)*2 * .pi/10
                beam(SCNVector3(x,0,0),SCNVector3(x,cos(a)*0.59,sin(a)*0.59),0.035,planks[0],parent:wheel)
                let peg=SCNSphere(radius:0.016);peg.segmentCount=8
                add(peg,SCNVector3(x*1.10,cos(a)*0.46,sin(a)*0.46),iron,parent:wheel)
            }
        }
        for i in 0..<24 {
            let a=Float(i)*2 * .pi/24
            let paddle=box(0.36,0.085,0.14,0,cos(a)*0.62,sin(a)*0.62,planks[i%4],parent:wheel)
            paddle.eulerAngles.x = a
        }
        let axle=SCNCylinder(radius:0.065,height:1.50);axle.radialSegmentCount=16
        add(axle,SCNVector3(-0.40,0.72,0),darkWood).eulerAngles.z = .pi/2
        let hub=SCNCylinder(radius:0.115,height:0.39);hub.radialSegmentCount=20
        add(hub,SCNVector3Zero,iron,parent:wheel).eulerAngles.z = .pi/2
        // Bank-side bearing support and retaining stones.
        for z: Float in [-0.28,0.28] {
            beam(SCNVector3(-0.30,0.07,z),SCNVector3(-0.30,0.75,0),0.045,timber)
        }
        for i in 0..<6 { box(0.18,0.12,0.20,-0.35,0.07,Float(i)*0.25-0.63,rocks[i%4]) }
        // Flour sacks and a barrel make the building read as a working mill.
        let sackMaterial=material(0.69,0.60,0.40)
        for i in 0..<2 {
            let sack=SCNSphere(radius:0.14);sack.segmentCount=16
            add(sack,SCNVector3(0.96+Float(i)*0.17,0.25,0.81),sackMaterial).scale=SCNVector3(0.7,1.25,0.7)
        }
        let barrel=SCNCylinder(radius:0.12,height:0.28);barrel.radialSegmentCount=16
        add(barrel,SCNVector3(-0.04,0.22,0.89),planks[1])
        for y: Float in [0.13,0.31] {
            let band=SCNTorus(ringRadius:0.122,pipeRadius:0.009);band.ringSegmentCount=24;band.pipeSegmentCount=6
            add(band,SCNVector3(-0.04,y,0.89),iron)
        }
        return root
    }

    static func obstacles(in root: SCNNode) -> [SCNVector3] {
        guard let mill = root.childNode(withName: "waterMill", recursively: false), !mill.isHidden else { return [] }
        return [mill.convertPosition(SCNVector3(0.48,0,0), to: nil)]
    }

    static func animate(_ root: SCNNode, moving: Bool, night: Bool) {
        if let wheel=root.childNode(withName:"millWheel",recursively:false) {
            if moving && wheel.action(forKey:"millTurn") == nil {
                wheel.runAction(.repeatForever(.rotateBy(x:2 * .pi,y:0,z:0,duration:14)),forKey:"millTurn")
            } else if !moving { wheel.removeAction(forKey:"millTurn") }
        }
        root.enumerateChildNodes { node,_ in
            if node.name == "millWindow" { node.geometry?.firstMaterial?.emission.intensity = night ? 0.75 : 0.12 }
        }
    }
}

// The seat and ropes share one pivot, so they always swing together.
enum ForestSwingAsset {
    static func make() -> SCNNode {
        let root = SCNNode(); root.name = "forestSwing"
        func material(_ color: UIColor) -> SCNMaterial {
            let m = SCNMaterial(); m.diffuse.contents = color
            m.lightingModel = .physicallyBased; m.roughness.contents = 0.85
            return m
        }
        let wood = material(UIColor(red: 0.39, green: 0.25, blue: 0.14, alpha: 1))
        let honey = material(UIColor(red: 0.61, green: 0.43, blue: 0.25, alpha: 1))
        let rope = material(UIColor(red: 0.72, green: 0.64, blue: 0.44, alpha: 1))
        let iron = material(.darkGray); iron.metalness.contents = 0.65
        let stone = material(UIColor(red: 0.53, green: 0.55, blue: 0.45, alpha: 1))
        let green = material(UIColor(red: 0.23, green: 0.43, blue: 0.19, alpha: 1))
        @discardableResult
        func add(_ shape: SCNGeometry, _ position: SCNVector3, _ m: SCNMaterial, to parent: SCNNode) -> SCNNode {
            shape.materials = [m]
            let n = SCNNode(geometry: shape); n.position = position; parent.addChildNode(n); return n
        }
        func beam(_ a: SCNVector3, _ b: SCNVector3, radius: CGFloat, material: SCNMaterial, parent: SCNNode) {
            let delta = SCNVector3(b.x-a.x,b.y-a.y,b.z-a.z)
            let length = sqrt(delta.x*delta.x+delta.y*delta.y+delta.z*delta.z)
            let cylinder = SCNCylinder(radius: radius, height: CGFloat(length)); cylinder.radialSegmentCount = 12
            let pivot = SCNNode(); pivot.position = SCNVector3((a.x+b.x)/2,(a.y+b.y)/2,(a.z+b.z)/2)
            parent.addChildNode(pivot)
            pivot.look(at: parent.convertPosition(b, to: nil))
            add(cylinder, SCNVector3Zero, material, to: pivot).eulerAngles.x = .pi/2
        }
        for x: Float in [-0.9,0.9] {
            for z: Float in [-0.58,0.58] {
                beam(SCNVector3(x,0.1,z),SCNVector3(x,2.25,0),radius:0.075,material:wood,parent:root)
                let foot = SCNCylinder(radius: 0.15, height: 0.1); foot.radialSegmentCount = 10
                add(foot, SCNVector3(x,0.05,z),stone,to:root)
            }
            beam(SCNVector3(x,0.84,-0.4),SCNVector3(x,0.84,0.4),radius:0.045,material:honey,parent:root)
            beam(SCNVector3(x,1.65,0),SCNVector3(x*0.55,2.25,0),radius:0.043,material:wood,parent:root)
            let bolt = SCNSphere(radius:0.036); bolt.segmentCount = 10
            add(bolt,SCNVector3(x,2.25,0.076),iron,to:root)
        }
        beam(SCNVector3(-1.08,2.25,0),SCNVector3(1.08,2.25,0),radius:0.09,material:wood,parent:root)
        let pivot = SCNNode(); pivot.name = "swingSeat"; pivot.position.y = 2.18; root.addChildNode(pivot)
        for x: Float in [-0.48,0.48] {
            let ring = SCNTorus(ringRadius:0.062,pipeRadius:0.013); ring.ringSegmentCount = 16; ring.pipeSegmentCount = 6
            add(ring,SCNVector3(x,2.24,0),iron,to:root).eulerAngles.z = .pi/2
            for z: Float in [-0.16,0.16] {
                beam(SCNVector3(x,-0.04,0),SCNVector3(x,-1.6,z),radius:0.014,material:rope,parent:pivot)
            }
        }
        for i in 0..<4 {
            let plank = SCNBox(width:1.12,height:0.065,length:0.092,chamferRadius:0.018)
            add(plank,SCNVector3(0,-1.6,Float(i)*0.105-0.1575),honey,to:pivot)
        }
        for x: Float in [-0.4,0.4] {
            add(SCNBox(width:0.065,height:0.06,length:0.44,chamferRadius:0.012),SCNVector3(x,-1.66,0),wood,to:pivot)
        }
        let petals = [material(.init(red:0.96,green:0.79,blue:0.45,alpha:1)), material(.init(red:0.86,green:0.61,blue:0.73,alpha:1)), material(.init(red:0.94,green:0.93,blue:0.81,alpha:1))]
        for i in 0..<20 {
            let side: Float = i % 2 == 0 ? -1 : 1
            let x = side * (0.86 + Float(i % 3)*0.09), z = Float(i/2)*0.14-0.63
            let height = Float(0.15 + Double(i%4)*0.025)
            beam(SCNVector3(x,0.03,z),SCNVector3(x,height,z),radius:0.009,material:green,parent:root)
            for j in 0..<5 {
                let angle = Float(j)*2 * .pi/5
                let petal = SCNSphere(radius:0.037); petal.segmentCount = 8
                let n = add(petal,SCNVector3(x+cos(angle)*0.034,height,z+sin(angle)*0.034),petals[i%3],to:root)
                n.scale = SCNVector3(1,0.42,1)
            }
            let center = SCNSphere(radius:0.021); center.segmentCount = 8
            add(center,SCNVector3(x,height+0.009,z),honey,to:root)
        }
        return root
    }

    static func animate(_ root: SCNNode, moving: Bool) {
        guard let seat = root.childNode(withName: "swingSeat", recursively: false) else { return }
        if moving && seat.action(forKey: "swing") == nil {
            let action = SCNAction.customAction(duration: 4.8) { node, elapsed in
                node.eulerAngles.x = Float(sin(Double(elapsed) / 4.8 * 2 * .pi) * 0.11)
            }
            seat.runAction(.repeatForever(action), forKey: "swing")
        } else if !moving {
            seat.removeAction(forKey: "swing"); seat.eulerAngles.x = 0
        }
    }

    static func obstacles(in root: SCNNode) -> [SCNVector3] {
        guard let swing = root.childNode(withName: "forestSwing", recursively: false), !swing.isHidden else { return [] }
        return [-0.6,0.6].map { swing.convertPosition(SCNVector3($0,0,0), to: nil) }
    }
}
