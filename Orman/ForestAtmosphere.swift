import SwiftUI
import CoreLocation
import SceneKit
import UIKit

// No task data or persistent location history is sent to the weather service.
enum ForestWeather: String {
    case clear, cloudy, fog, rain, snow, storm
    init(code: Int) {
        switch code {
        case 0, 1: self = .clear
        case 2, 3: self = .cloudy
        case 45, 48: self = .fog
        case 51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 80, 81, 82: self = .rain
        case 71, 73, 75, 77, 85, 86: self = .snow
        case 95, 96, 99: self = .storm
        default: self = .cloudy
        }
    }
    var title: String {
        switch self {
        case .clear: return T("Açık", "Clear", "Klar")
        case .cloudy: return T("Bulutlu", "Cloudy", "Bewölkt")
        case .fog: return T("Sisli", "Foggy", "Neblig")
        case .rain: return T("Yağmurlu", "Rainy", "Regnerisch")
        case .snow: return T("Karlı", "Snowy", "Schnee")
        case .storm: return T("Fırtınalı", "Stormy", "Stürmisch")
        }
    }
    var icon: String {
        switch self {
        case .clear: return "sun.max.fill"
        case .cloudy: return "cloud.fill"
        case .fog: return "cloud.fog.fill"
        case .rain: return "cloud.rain.fill"
        case .snow: return "cloud.snow.fill"
        case .storm: return "cloud.bolt.rain.fill"
        }
    }
}

// Mirrors DaylightMode/SeasonMode: automatic by default (tied to the real,
// location-based reading), or the user can pin the forest to a specific
// condition regardless of what's actually happening outside — useful both
// as a creative choice and to preview rain, snow or clouds on demand.
enum WeatherMode: String, Codable, CaseIterable, Identifiable {
    case automatic, clear, cloudy, fog, rain, snow, storm
    var id: String { rawValue }
    var title: String {
        switch self {
        case .automatic: return T("Otomatik", "Automatic", "Automatisch")
        case .clear: return ForestWeather.clear.title
        case .cloudy: return ForestWeather.cloudy.title
        case .fog: return ForestWeather.fog.title
        case .rain: return ForestWeather.rain.title
        case .snow: return ForestWeather.snow.title
        case .storm: return ForestWeather.storm.title
        }
    }
    var icon: String {
        switch self {
        case .automatic: return "location.fill"
        case .clear: return ForestWeather.clear.icon
        case .cloudy: return ForestWeather.cloudy.icon
        case .fog: return ForestWeather.fog.icon
        case .rain: return ForestWeather.rain.icon
        case .snow: return ForestWeather.snow.icon
        case .storm: return ForestWeather.storm.icon
        }
    }
    func resolved(real: ForestWeather?) -> ForestWeather? {
        switch self {
        case .automatic: return real
        case .clear: return .clear
        case .cloudy: return .cloudy
        case .fog: return .fog
        case .rain: return .rain
        case .snow: return .snow
        case .storm: return .storm
        }
    }
}

struct WeatherReading {
    let condition: ForestWeather
    let temperature: Double
    let date: Date
    func isFresh(at now: Date) -> Bool { (-300...3600).contains(now.timeIntervalSince(date)) }
}

struct WeatherResponse: Decodable {
    struct Current: Decodable {
        let time: Double
        let temperature_2m: Double
        let weather_code: Int
    }
    let current: Current
    func reading(now: Date) throws -> WeatherReading {
        let result = WeatherReading(condition: ForestWeather(code: current.weather_code), temperature: current.temperature_2m, date: Date(timeIntervalSince1970: current.time))
        guard result.temperature.isFinite, (-100...70).contains(result.temperature), result.isFresh(at: now) else {
            throw URLError(.cannotParseResponse)
        }
        return result
    }
}

@MainActor
final class ForestWeatherService: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    @Published private(set) var enabled = UserDefaults.standard.bool(forKey: "forest.localWeather.enabled")
    @Published private(set) var reading: WeatherReading?
    @Published private(set) var message = "Hava durumu kapalı; telefon saati kullanılıyor."
    @Published private(set) var busy = false
    @Published private(set) var denied = false
    private let manager = CLLocationManager()
    private var lastAttempt = Date.distantPast
    private var fetchTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var requestID = UUID()
    private var foreground = true

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func setEnabled(_ value: Bool) {
        enabled = value
        UserDefaults.standard.set(value, forKey: "forest.localWeather.enabled")
        if value {
            if manager.authorizationStatus == .notDetermined {
                message = T("Konum izni bekleniyor.", "Waiting for location permission.", "Warte auf Standortzugriff.")
                manager.requestWhenInUseAuthorization()
            } else { refresh(force: true) }
        } else {
            cancel()
            reading = nil
            message = T("Hava durumu kapalı; telefon saati kullanılıyor.", "Weather is off; using your phone's clock.", "Wetter ist aus; die Uhrzeit deines Handys wird verwendet.")
        }
    }

    func setForeground(_ active: Bool) {
        foreground = active
        if active { refresh() } else {
            if busy { lastAttempt = .distantPast }
            cancel()
        }
    }

    func refresh(force: Bool = false) {
        guard enabled, foreground else { return }
        let auth = manager.authorizationStatus
        denied = auth == .denied || auth == .restricted
        guard auth == .authorizedAlways || auth == .authorizedWhenInUse else {
            reading = nil
            message = denied ? T("Konum izni kapalı. Saat görünümü etkin.", "Location permission is off. Using clock-based view.", "Standortzugriff ist aus. Die Uhrzeit-Ansicht ist aktiv.") : T("Yerel hava için konum izni gerekli.", "Location permission is needed for local weather.", "Für lokales Wetter wird der Standortzugriff benötigt.")
            return
        }
        guard !busy else { return }
        let interval: TimeInterval = reading?.isFresh(at: Date()) == true ? 1200 : 300
        guard force || Date().timeIntervalSince(lastAttempt) >= interval else { return }
        lastAttempt = Date()
        busy = true
        message = T("Yaklaşık konum alınıyor…", "Getting approximate location…", "Ungefährer Standort wird ermittelt…")
        manager.requestLocation()
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 20_000_000_000) } catch { return }
            guard let self, self.busy else { return }
            self.cancel()
            self.message = T("Konum alınamadı. Daha sonra yeniden deneyebilirsin.", "Couldn't get your location. You can try again later.", "Dein Standort konnte nicht ermittelt werden. Du kannst es später erneut versuchen.")
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        denied = manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted
        if denied {
            cancel()
            reading = nil
            message = T("Konum izni kapalı. Saat görünümü etkin.", "Location permission is off. Using clock-based view.", "Standortzugriff ist aus. Die Uhrzeit-Ansicht ist aktiv.")
        } else if enabled { refresh(force: true) }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard busy else { return }
        cancel()
        message = T("Konum alınamadı. Saat görünümü çalışmaya devam ediyor.", "Couldn't get your location. The clock-based view keeps working.", "Dein Standort konnte nicht ermittelt werden. Die Uhrzeit-Ansicht funktioniert weiterhin.")
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard busy, enabled, foreground, fetchTask == nil,
              let location = locations.last,
              location.horizontalAccuracy >= 0,
              abs(location.timestamp.timeIntervalSinceNow) < 300 else { return }
        timeoutTask?.cancel()
        // Round to about 1 km before sending. Coordinates are not persisted.
        let lat = (location.coordinate.latitude * 100).rounded() / 100
        let lon = (location.coordinate.longitude * 100).rounded() / 100
        var parts = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        parts.queryItems = [
            URLQueryItem(name: "latitude", value: String(lat)),
            URLQueryItem(name: "longitude", value: String(lon)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code"),
            URLQueryItem(name: "timeformat", value: "unixtime"),
            URLQueryItem(name: "forecast_days", value: "1")
        ]
        let id = UUID()
        requestID = id
        message = T("Hava durumu güncelleniyor…", "Updating weather…", "Wetter wird aktualisiert…")
        fetchTask = Task { [weak self] in
            guard let self else { return }
            do {
                var request = URLRequest(url: parts.url!)
                request.timeoutInterval = 15
                request.cachePolicy = .reloadIgnoringLocalCacheData
                let configuration = URLSessionConfiguration.ephemeral
                let session = URLSession(configuration: configuration)
                defer { session.finishTasksAndInvalidate() }
                let (data, response) = try await session.data(for: request)
                try Task.checkCancellation()
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw URLError(.badServerResponse) }
                let value = try JSONDecoder().decode(WeatherResponse.self, from: data).reading(now: Date())
                guard self.requestID == id, self.enabled else { return }
                self.reading = value
                self.message = T("Yaklaşık konumuna göre hava durumu.", "Weather based on your approximate location.", "Wetter basierend auf deinem ungefähren Standort.")
            } catch {
                guard self.requestID == id else { return }
                self.message = T("Hava durumu yenilenemedi. Güncel veri yoksa saat görünümü kullanılır.", "Couldn't refresh the weather. The clock-based view is used without current data.", "Wetter konnte nicht aktualisiert werden. Ohne aktuelle Daten wird die Uhrzeit-Ansicht verwendet.")
            }
            guard self.requestID == id else { return }
            self.busy = false
            self.fetchTask = nil
        }
    }

    private func cancel() {
        requestID = UUID()
        manager.stopUpdatingLocation()
        fetchTask?.cancel()
        fetchTask = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        busy = false
    }

    func current(at date: Date) -> WeatherReading? {
        guard enabled, let reading, reading.isFresh(at: date) else { return nil }
        return reading
    }
}

struct WeatherSettings: View {
    @ObservedObject var service: ForestWeatherService
    @Binding var daylightMode: DaylightMode
    @Binding var seasonMode: SeasonMode
    @Binding var weatherMode: WeatherMode
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(T("Konuma göre hava durumu", "Location-based weather", "Standortbasiertes Wetter"), isOn: Binding(get: { service.enabled }, set: { service.setEnabled($0) }))
                    Text(service.message).font(.subheadline).foregroundStyle(.secondary)
                    if let reading = service.current(at: Date()) {
                        Label("\(reading.condition.title) · \(Int(reading.temperature.rounded()))°C", systemImage: reading.condition.icon)
                        Text(T("Veri zamanı: \(reading.date.formatted(date: .omitted, time: .shortened))", "Data time: \(reading.date.formatted(date: .omitted, time: .shortened))", "Datenzeit: \(reading.date.formatted(date: .omitted, time: .shortened))"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if service.enabled {
                        Button(service.busy ? T("Güncelleniyor…", "Updating…", "Wird aktualisiert…") : T("Yenile", "Refresh", "Aktualisieren")) { service.refresh(force: true) }.disabled(service.busy)
                    }
                    if service.denied {
                        Button(T("Konum ayarlarını aç", "Open location settings", "Standorteinstellungen öffnen")) {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        }
                    }
                } footer: {
                    Text(T("Yaklaşık konumun yalnızca hava durumunu almak için Open-Meteo’ya gönderilir. Görevlerin paylaşılmaz; uygulama konum geçmişi saklamaz. Arka planda konum izlenmez.", "Your approximate location is sent to Open-Meteo only to fetch the weather. Your tasks aren't shared; the app doesn't store location history. Location isn't tracked in the background.", "Dein ungefährer Standort wird nur an Open-Meteo gesendet, um das Wetter abzurufen. Deine Aufgaben werden nicht geteilt; die App speichert keinen Standortverlauf. Im Hintergrund wird kein Standort erfasst."))
                }
                Section {
                    Picker(T("Gündüz/gece", "Day/night", "Tag/Nacht"), selection: $daylightMode) {
                        ForEach(DaylightMode.allCases) { mode in Text(mode.title).tag(mode) }
                    }
                } header: {
                    Text(T("Gökyüzü", "Sky", "Himmel"))
                } footer: {
                    Text(T("Gündüz veya gece seçersen ormanın her zaman o şekilde görünür.", "Choosing Day or Night keeps your forest looking that way all the time.", "Wenn du Tag oder Nacht wählst, sieht dein Wald immer so aus."))
                }
                Section {
                    Picker(T("Mevsim", "Season", "Jahreszeit"), selection: $seasonMode) {
                        ForEach(SeasonMode.allCases) { mode in Text(mode.title).tag(mode) }
                    }
                    Text(T("Zeminin ve yaprakların rengi seçili mevsime göre değişir.", "The ground and leaf colors change to match the selected season.", "Die Farbe von Boden und Blättern richtet sich nach der gewählten Jahreszeit."))
                        .font(.caption).foregroundStyle(.secondary)
                } header: {
                    Text(T("Mevsim", "Season", "Jahreszeit"))
                } footer: {
                    Text(T("Otomatik, telefonunun takvim ayına göre kış/ilkbahar/yaz/sonbahar arasında geçiş yapar.", "Automatic switches between winter/spring/summer/autumn based on your phone's calendar month.", "Automatisch wechselt basierend auf dem Kalendermonat deines Telefons zwischen Winter/Frühling/Sommer/Herbst."))
                }
                Section {
                    Picker(T("Hava durumu", "Weather", "Wetter"), selection: $weatherMode) {
                        ForEach(WeatherMode.allCases) { mode in Label(mode.title, systemImage: mode.icon).tag(mode) }
                    }
                    Text(T("Belirli bir hava durumu seçersen, yukarıdaki konuma göre hava durumu yerine o kullanılır.", "Choosing a specific condition overrides the location-based weather above.", "Wählst du eine bestimmte Wetterlage, ersetzt sie das oben stehende standortbasierte Wetter."))
                        .font(.caption).foregroundStyle(.secondary)
                } header: {
                    Text(T("Hava durumu", "Weather", "Wetter"))
                } footer: {
                    Text(T("Otomatik, konuma göre hava durumu açıksa onu kullanır; kapalıysa açık gökyüzü varsayılır.", "Automatic uses the location-based weather when it's on, or assumes clear skies when it's off.", "Automatisch verwendet das standortbasierte Wetter, wenn es aktiviert ist, sonst wird von klarem Himmel ausgegangen."))
                }
                Section(T("Veri kaynağı", "Data source", "Datenquelle")) {
                    Link(T("Hava durumu: Open-Meteo (CC BY 4.0)", "Weather: Open-Meteo (CC BY 4.0)", "Wetter: Open-Meteo (CC BY 4.0)"), destination: URL(string: "https://open-meteo.com/")!)
                }
            }
            .navigationTitle(T("Gökyüzü ve hava", "Sky and weather", "Himmel und Wetter"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(T("Bitti", "Done", "Fertig")) { dismiss() } } }
            .environment(\.locale, L10n.locale)
        }
    }
}

// Calendar.current deliberately follows the device's local time zone.
struct ForestDaylight {
    let hour: Double
    init(date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        hour = Double(parts.hour ?? 12) + Double(parts.minute ?? 0) / 60
    }
    var strength: Double { max(0, sin((hour - 6) / 12 * .pi)) }
    var night: Bool { hour < 6 || hour >= 18 }
    var title: String {
        switch hour {
        case 5..<8: return T("Sabah ışığı", "Morning light", "Morgenlicht")
        case 8..<17: return T("Gündüz", "Daytime", "Tag")
        case 17..<20: return T("Akşam ışığı", "Evening light", "Abendlicht")
        default: return T("Gece", "Night", "Nacht")
        }
    }
    var icon: String { night ? "moon.stars.fill" : "sun.max.fill" }
}

// Northern-hemisphere meteorological seasons, from the device's own
// calendar month — no location lookup involved.
enum ForestSeason: Int, Equatable {
    case winter, spring, summer, autumn
    init(date: Date, calendar: Calendar = .current) {
        switch calendar.component(.month, from: date) {
        case 12, 1, 2: self = .winter
        case 3, 4, 5: self = .spring
        case 6, 7, 8: self = .summer
        default: self = .autumn
        }
    }
    var title: String {
        switch self {
        case .winter: return T("Kış", "Winter", "Winter")
        case .spring: return T("İlkbahar", "Spring", "Frühling")
        case .summer: return T("Yaz", "Summer", "Sommer")
        case .autumn: return T("Sonbahar", "Autumn", "Herbst")
        }
    }
}

// Automatic by default (tied to the phone's clock), or the user can pin the
// forest to always look like day or always look like night.
enum DaylightMode: String, Codable, CaseIterable, Identifiable {
    case automatic, day, night
    var id: String { rawValue }
    var title: String {
        switch self {
        case .automatic: return T("Otomatik", "Automatic", "Automatisch")
        case .day: return T("Gündüz", "Day", "Tag")
        case .night: return T("Gece", "Night", "Nacht")
        }
    }
}

// Mirrors the day/night mode above: automatic by default (tied to the
// calendar month), or the user can pin the forest to one season.
enum SeasonMode: String, Codable, CaseIterable, Identifiable {
    case automatic, winter, spring, summer, autumn
    var id: String { rawValue }
    var title: String {
        switch self {
        case .automatic: return T("Otomatik", "Automatic", "Automatisch")
        case .winter: return ForestSeason.winter.title
        case .spring: return ForestSeason.spring.title
        case .summer: return ForestSeason.summer.title
        case .autumn: return ForestSeason.autumn.title
        }
    }
    func resolved(for date: Date) -> ForestSeason {
        switch self {
        case .automatic: return ForestSeason(date: date)
        case .winter: return .winter
        case .spring: return .spring
        case .summer: return .summer
        case .autumn: return .autumn
        }
    }
}


struct AtmosphereRenderer {
    static func apply(to view: SCNView, date: Date, weather: ForestWeather?, radius: Double, reduceMotion: Bool, changed: Bool, active: Bool = true) {
        guard let scene = view.scene else { return }
        let daylight = ForestDaylight(date: date)
        let shade = weather == nil || weather == .clear ? 1.0 : (weather == .cloudy ? 0.7 : 0.45)
        let colors = palette(hour: daylight.hour, overcast: shade < 1)
        if changed {
            scene.background.contents = skyImage(daylight: daylight, weather: weather, top: colors.0, bottom: colors.1)
        }
        view.backgroundColor = colors.0
        scene.fogColor = colors.1
        scene.fogStartDistance = weather == .fog ? radius * 2.8 : radius * 5
        scene.fogEndDistance = weather == .fog ? radius * 7 : radius * 12
        let root = scene.rootNode
        let sun = root.childNode(withName: "sunlight", recursively: false)
        sun?.light?.intensity = CGFloat(180 + daylight.strength * 1100 * shade)
        sun?.light?.color = daylight.night ? UIColor(red: 0.65, green: 0.75, blue: 1, alpha: 1) : UIColor(red: 1, green: 0.78 + daylight.strength * 0.16, blue: 0.58 + daylight.strength * 0.3, alpha: 1)
        let angle = (daylight.hour - 6) / 12 * .pi
        // Height nudged down 40%, then another 3%, from its original arc.
        sun?.position = SCNVector3(cos(angle) * radius, max(4, sin(angle) * radius * 1.164), -radius * 0.5)
        sun?.look(at: SCNVector3Zero)
        // The visible sun disc only shows by day, in clear-ish weather, and
        // warms up toward the horizon the same way the old flat-painted
        // version did.
        let cloudy = weather != nil && weather != .clear
        let sunVisible = !daylight.night && !cloudy
        let warmth = min(1, max(0, 1 - daylight.strength * 1.15))
        sun?.childNode(withName: "sunOrbCore", recursively: false)?.isHidden = !sunVisible
        sun?.childNode(withName: "sunOrbGlow", recursively: false)?.isHidden = !sunVisible
        if let coreMaterial = sun?.childNode(withName: "sunOrbCore", recursively: false)?.geometry?.firstMaterial {
            coreMaterial.emission.contents = UIColor(red: 1, green: 0.97 - warmth * 0.12, blue: 0.86 - warmth * 0.55, alpha: 1)
        }
        // The moon arcs across the night sky the same way the sun arcs
        // across the day, rising at 18:00, peaking near midnight, setting
        // by 06:00 — real 3D motion instead of a fixed painted spot.
        let moon = root.childNode(withName: "moonOrb", recursively: false)
        let nightHour = daylight.hour < 6 ? daylight.hour + 24 : daylight.hour
        let moonAngle = (nightHour - 18) / 12 * .pi
        // Height nudged down 45% from its original arc, and shifted 20%
        // further right (along the arc's own x-axis).
        moon?.position = SCNVector3(cos(moonAngle) * radius + radius * 0.2, max(4, sin(moonAngle) * radius * 1.1), -radius * 0.5)
        moon?.isHidden = !daylight.night || cloudy
        // Clouds are real 3D puffs drifting around the forest on their own
        // slow rotation (see ContentView's "clouds" node group), rather
        // than sprites painted onto the flat sky backdrop — so, like the
        // sun and moon, orbiting the camera reveals their actual depth.
        if let clouds = root.childNode(withName: "clouds", recursively: false) {
            clouds.isHidden = !cloudy
            if cloudy {
                let heavy = weather == .rain || weather == .storm || weather == .snow
                let texture = heavy ? stormCloudTexture : fairCloudTexture
                let layerOpacity: [CGFloat] = [0.5, 0.4, 0.85]
                for i in 0..<3 {
                    guard let layer = clouds.childNode(withName: "cloudLayer\(i)", recursively: false) else { continue }
                    for puff in layer.childNodes {
                        puff.opacity = layerOpacity[i] * (daylight.night ? 0.16 : 1)
                        puff.geometry?.firstMaterial?.diffuse.contents = texture
                    }
                }
            }
        }
        root.childNode(withName: "ambientLight", recursively: false)?.light?.intensity = CGFloat(270 + daylight.strength * 250)
        root.childNode(withName: "fillLight", recursively: false)?.light?.intensity = CGFloat(100 + daylight.strength * 120)
        guard changed else { return }
        root.childNode(withName: "weatherParticles", recursively: false)?.removeFromParentNode()
        root.childNode(withName: "rainSplashes", recursively: false)?.removeFromParentNode()
        guard !reduceMotion, let weather, [.rain, .snow, .storm].contains(weather) else { return }
        let snow = weather == .snow
        let storm = weather == .storm
        let particles = SCNParticleSystem()
        // A proper downpour reads by volume: storm rains harder and faster
        // than a plain shower, and both now fall thick enough to actually
        // notice, rather than the sparse drizzle this used to be.
        particles.birthRate = snow ? 60 : (storm ? 640 : 420)
        particles.particleLifeSpan = snow ? 5 : 0.75
        particles.particleLifeSpanVariation = snow ? 1.2 : 0.12
        particles.particleSize = snow ? 0.12 : (storm ? 0.05 : 0.042)
        particles.particleSizeVariation = snow ? 0.03 : 0.012
        particles.particleVelocity = snow ? 2.2 : (storm ? 22 : 16)
        particles.particleVelocityVariation = snow ? 0.6 : 2.5
        // A small nudge of stretch along the fall direction, just enough to
        // read as a streak rather than a dot — stretchFactor scales with
        // velocity, so anything much above this turns raindrops into
        // room-spanning icicles.
        particles.stretchFactor = snow ? 0 : 0.025
        particles.spreadingAngle = snow ? 8 : (storm ? 6 : 3)
        particles.emittingDirection = SCNVector3(0, -1, 0)
        particles.acceleration = SCNVector3(snow ? 0.12 : (storm ? 0.6 : 0.35), 0, 0)
        particles.emitterShape = SCNBox(width: radius * 2.1, height: 0.01, length: radius * 2.1, chamferRadius: 0)
        particles.particleColor = snow ? .white : UIColor(red: 0.8, green: 0.88, blue: 1, alpha: storm ? 0.8 : 0.68)
        particles.particleImage = precipitationImage(snow: snow)
        particles.isLightingEnabled = false
        particles.blendMode = .alpha
        let emitter = SCNNode()
        emitter.name = "weatherParticles"
        emitter.position.y = 11
        emitter.addParticleSystem(particles)
        root.addChildNode(emitter)
        guard !snow else { return }
        // Small rings where the rain actually lands, so the ground reads as
        // wet and struck rather than the drops just vanishing at y=0.
        let splashes = SCNParticleSystem()
        splashes.birthRate = storm ? 130 : 80
        splashes.particleLifeSpan = 0.28
        splashes.particleLifeSpanVariation = 0.08
        splashes.particleSize = storm ? 0.16 : 0.12
        splashes.particleSizeVariation = 0.04
        splashes.particleVelocity = 0
        splashes.spreadingAngle = 180
        splashes.emitterShape = SCNBox(width: radius * 2.1, height: 0.01, length: radius * 2.1, chamferRadius: 0)
        splashes.birthLocation = .volume
        splashes.particleColor = UIColor(red: 0.85, green: 0.92, blue: 1, alpha: 0.5)
        splashes.particleImage = splashRingImage()
        splashes.isLightingEnabled = false
        splashes.blendMode = .additive
        let splashEmitter = SCNNode()
        splashEmitter.name = "rainSplashes"
        splashEmitter.position.y = 0.06
        splashEmitter.addParticleSystem(splashes)
        root.addChildNode(splashEmitter)
    }

    static func palette(hour: Double, overcast: Bool) -> (UIColor, UIColor) {
        let stops: [(Double, UIColor, UIColor)] = [
            (0, UIColor(red: 0.06, green: 0.10, blue: 0.20, alpha: 1), UIColor(red: 0.19, green: 0.27, blue: 0.33, alpha: 1)),
            (5, UIColor(red: 0.10, green: 0.15, blue: 0.29, alpha: 1), UIColor(red: 0.34, green: 0.34, blue: 0.44, alpha: 1)),
            (6.5, UIColor(red: 0.51, green: 0.64, blue: 0.77, alpha: 1), UIColor(red: 0.98, green: 0.77, blue: 0.58, alpha: 1)),
            (9, UIColor(red: 0.53, green: 0.77, blue: 0.89, alpha: 1), UIColor(red: 0.88, green: 0.93, blue: 0.85, alpha: 1)),
            (16, UIColor(red: 0.53, green: 0.77, blue: 0.89, alpha: 1), UIColor(red: 0.88, green: 0.93, blue: 0.85, alpha: 1)),
            (18, UIColor(red: 0.44, green: 0.43, blue: 0.64, alpha: 1), UIColor(red: 0.98, green: 0.65, blue: 0.42, alpha: 1)),
            (20, UIColor(red: 0.06, green: 0.10, blue: 0.20, alpha: 1), UIColor(red: 0.19, green: 0.27, blue: 0.33, alpha: 1)),
            (24, UIColor(red: 0.06, green: 0.10, blue: 0.20, alpha: 1), UIColor(red: 0.19, green: 0.27, blue: 0.33, alpha: 1))
        ]
        let index = (0..<(stops.count - 1)).first { hour < stops[$0 + 1].0 } ?? stops.count - 2
        let a = stops[index], b = stops[index + 1]
        let progress = CGFloat((hour - a.0) / (b.0 - a.0))
        func blend(_ left: UIColor, _ right: UIColor) -> UIColor {
            var r: CGFloat = 0, g: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            var rr: CGFloat = 0, gg: CGFloat = 0, bb: CGFloat = 0, aa: CGFloat = 0
            left.getRed(&r, green: &g, blue: &blue, alpha: &alpha)
            right.getRed(&rr, green: &gg, blue: &bb, alpha: &aa)
            let saturation: CGFloat = overcast ? 0.45 : 1
            let red = r + (rr - r) * progress, green = g + (gg - g) * progress, blueValue = blue + (bb - blue) * progress
            let gray = (red + green + blueValue) / 3
            return UIColor(red: gray + (red - gray) * saturation, green: gray + (green - gray) * saturation, blue: gray + (blueValue - gray) * saturation, alpha: 1)
        }
        return (blend(a.1, b.1), blend(a.2, b.2))
    }

    static func skyImage(daylight: ForestDaylight, weather: ForestWeather?, top: UIColor, bottom: UIColor) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        return UIGraphicsImageRenderer(size: CGSize(width: 512, height: 1024), format: format).image { renderer in
            let ctx = renderer.cgContext
            let colors = [top.cgColor, bottom.cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: 1024), options: [])
            }
            let cloudy = weather != nil && weather != .clear
            if daylight.night && !cloudy {
                for i in 0..<55 {
                    UIColor.white.withAlphaComponent(CGFloat(i % 4 + 1) * 0.16).setFill()
                    ctx.fillEllipse(in: CGRect(x: (i * 137 + 19) % 512, y: (i * 79 + 31) % 550, width: i % 3 == 0 ? 2 : 1, height: i % 3 == 0 ? 2 : 1))
                }
            }
            // The sun, moon and clouds are all real 3D objects in the scene
            // now (see ContentView's sunOrb/moonOrb/clouds nodes) rather
            // than painted onto this flat backdrop, so they move properly
            // with the camera instead of staying screen-locked.
        }
    }

    // Cache the expensive density map once; reused directly by ContentView
    // for the 3D cloud puffs, and by minute-by-minute sky updates here.
    static let fairCloudTexture = makeCloudTexture(storm: false)
    static let stormCloudTexture = makeCloudTexture(storm: true)

    static func makeCloudTexture(storm: Bool) -> CGImage? {
        let width = 768, height = 384
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        func hash(_ x: Int, _ y: Int) -> Double {
            var n = UInt64(bitPattern: Int64(x)) &* 374761393 &+ UInt64(bitPattern: Int64(y)) &* 668265263
            n = (n ^ (n >> 13)) &* 1274126177
            return Double((n ^ (n >> 16)) & 65535) / 65535
        }
        func noise(_ x: Double, _ y: Double) -> Double {
            let ix = Int(floor(x)), iy = Int(floor(y))
            let fx = x-Double(ix), fy = y-Double(iy)
            let u = fx*fx*(3-2*fx), v = fy*fy*(3-2*fy)
            let a = hash(ix,iy)*(1-u)+hash(ix+1,iy)*u
            let b = hash(ix,iy+1)*(1-u)+hash(ix+1,iy+1)*u
            return a*(1-v)+b*v
        }
        // Unequal overlapping lobes give a soft cumulus silhouette, not repeated ovals.
        let lobes: [(Double, Double, Double, Double)] = [
            (0.17,0.63,0.15,0.23), (0.32,0.46,0.20,0.31),
            (0.49,0.36,0.20,0.32), (0.67,0.49,0.20,0.30),
            (0.81,0.62,0.14,0.21), (0.50,0.67,0.34,0.20)
        ]
        for y in 0..<height {
            for x in 0..<width {
                let u = Double(x)/Double(width-1), v = Double(y)/Double(height-1)
                // Domain warping breaks up the perfectly round silhouette at two scales.
                let warpX = (noise(u*8+31,v*7)-0.5)*0.065
                let warpY = (noise(u*9,v*8+19)-0.5)*0.075
                let detail = noise(u*15,v*12)*0.52 + noise(u*34+13,v*27)*0.30 + noise(u*79,v*63+7)*0.18
                var envelope = -10.0
                var illumination = 0.0, totalWeight = 0.0
                for (cx,cy,rx,ry) in lobes {
                    let dx=(u+warpX-cx)/rx, dy=(v+warpY-cy)/ry
                    let volume = 1-dx*dx-dy*dy
                    // Smoothly blend neighbouring puffs rather than drawing separate discs.
                    let weight = exp(volume*5)
                    let normalZ = sqrt(max(0.04,volume))
                    let light = max(0,(-dx*0.35-dy*0.65+normalZ*0.68)/sqrt(dx*dx+dy*dy+normalZ*normalZ))
                    illumination += weight*light; totalWeight += weight
                    envelope = max(envelope,volume)
                }
                guard envelope > -0.22 else { continue }
                let density = max(0,min(1,(envelope+(detail-0.5)*0.55+0.06)/0.56))
                let alpha = density*density*(3-2*density)
                let shade = max(0,min(1,(v-0.30)/0.55))
                let lighting = illumination/max(0.0001,totalWeight)
                let value = (storm ? 0.52 : 0.73) + lighting*0.25 - shade*0.08 + (detail-0.5)*0.10
                let rgb = [value-0.025*shade, value, min(1,value+0.035*shade)]
                let i=(y*width+x)*4
                for c in 0..<3 { pixels[i+c] = UInt8(max(0,min(255,rgb[c]*alpha*255))) }
                pixels[i+3] = UInt8(alpha*255)
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width*4,
                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    private static func precipitationImage(snow: Bool) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        if snow {
            return UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16), format: format).image { renderer in
                UIColor.white.setFill()
                renderer.cgContext.fillEllipse(in: CGRect(x: 2, y: 2, width: 12, height: 12))
            }
        }
        // A soft-capped streak rather than a hard-edged bar, so a stretched,
        // fast-falling raindrop reads as a real drop of water and not a
        // flickering dash.
        return UIGraphicsImageRenderer(size: CGSize(width: 8, height: 20), format: format).image { renderer in
            let ctx = renderer.cgContext
            let colors = [
                UIColor.white.withAlphaComponent(0).cgColor,
                UIColor.white.withAlphaComponent(0.95).cgColor,
                UIColor.white.withAlphaComponent(0.95).cgColor,
                UIColor.white.withAlphaComponent(0).cgColor
            ] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.2, 0.82, 1]) {
                ctx.drawLinearGradient(gradient, start: CGPoint(x: 4, y: 0), end: CGPoint(x: 4, y: 20), options: [])
            }
        }
    }

    // A thin, fading ring for the splash where a raindrop meets the ground.
    private static func splashRingImage() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 24, height: 24), format: format).image { renderer in
            let ctx = renderer.cgContext
            ctx.setStrokeColor(UIColor.white.withAlphaComponent(0.85).cgColor)
            ctx.setLineWidth(2)
            ctx.strokeEllipse(in: CGRect(x: 3, y: 3, width: 18, height: 18))
        }
    }
}
