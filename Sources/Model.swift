import AppKit
import ScreenSaver

struct LocationSettings {
    var city: String
    var latitude: Double
    var longitude: Double
    static let defaults = LocationSettings(city: "Waterloo", latitude: 43.4643, longitude: -80.5204)
    static var storage: UserDefaults { ScreenSaverDefaults(forModuleWithName: "com.neosaver.screensaver") ?? .standard }
    static func load() -> LocationSettings {
        let d = storage
        guard let city = d.string(forKey: "city"), d.object(forKey: "latitude") != nil else { return .defaults }
        return LocationSettings(city: city, latitude: d.double(forKey: "latitude"), longitude: d.double(forKey: "longitude"))
    }
    func save() {
        let d = Self.storage
        d.set(city, forKey: "city"); d.set(latitude, forKey: "latitude"); d.set(longitude, forKey: "longitude")
        d.synchronize()
    }
}

struct ClockText {
    let hour: String
    let minute: String
    let second: String
    let period: String
    let weekday: String
    let date: String
    init(date: Date, timeZone: TimeZone = .current) {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        func format(_ pattern: String) -> String { f.dateFormat = pattern; return f.string(from: date).uppercased() }
        hour = format("hh"); minute = format("mm"); second = format("ss"); period = format("a")
        weekday = format("EEE"); self.date = format("MMM d")
    }
}

struct WeatherReading: Codable {
    let temperature: Double
    let code: Int
    let fetchedAt: Date
    let isDay: Bool
    init(temperature: Double, code: Int, fetchedAt: Date, isDay: Bool = true) {
        self.temperature = temperature; self.code = code; self.fetchedAt = fetchedAt; self.isDay = isDay
    }
    var symbol: String { Self.symbol(for: code, isDay: isDay) }
    static func symbol(for code: Int, isDay: Bool = true) -> String {
        switch code {
        case 0: return isDay ? "sun.max" : "moon"
        case 1: return isDay ? "cloud.sun" : "moon"
        case 2: return isDay ? "cloud.sun" : "cloud.moon"
        case 3: return "cloud"
        case 45, 48: return "cloud.fog"
        case 71...77, 85, 86: return "cloud.snow"
        case 95...99: return "cloud.bolt.rain"
        default: return "cloud.rain"
        }
    }
    static func decode(_ data: Data, now: Date = Date()) throws -> WeatherReading {
        struct Response: Decodable {
            struct Current: Decodable { let temperature_2m: Double; let weather_code: Int; let is_day: Int }
            let current: Current
        }
        let result = try JSONDecoder().decode(Response.self, from: data)
        return WeatherReading(temperature: result.current.temperature_2m, code: result.current.weather_code, fetchedAt: now, isDay: result.current.is_day == 1)
    }
}

final class WeatherService {
    var onChange: ((WeatherReading?) -> Void)?
    private var task: URLSessionDataTask?
    private var lastAttempt = Date.distantPast
    private var generation = 0
    private(set) var reading: WeatherReading?
    private var settings = LocationSettings.load()
    init() { loadCache() }
    private var cacheKey: String { "weather.\(settings.latitude).\(settings.longitude)" }
    private func loadCache() {
        guard let data = LocationSettings.storage.data(forKey: cacheKey),
              let value = try? JSONDecoder().decode(WeatherReading.self, from: data),
              Date().timeIntervalSince(value.fetchedAt) < 3600 else { reading = nil; return }
        reading = value
    }
    func reloadLocation() {
        stop(); settings = .load(); lastAttempt = .distantPast; loadCache(); onChange?(reading); refresh()
    }
    func stop() { generation += 1; task?.cancel(); task = nil }
    func refresh(now: Date = Date()) {
        if let reading, now.timeIntervalSince(reading.fetchedAt) >= 3600 { self.reading = nil; onChange?(nil) }
        guard task == nil, now.timeIntervalSince(lastAttempt) >= 900 else { return }
        lastAttempt = now
        let version = generation
        let url = URL(string: "https://api.open-meteo.com/v1/forecast?latitude=\(settings.latitude)&longitude=\(settings.longitude)&current=temperature_2m,weather_code,is_day&temperature_unit=celsius&forecast_days=1")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        task = URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            let value: WeatherReading? = {
                guard (response as? HTTPURLResponse)?.statusCode == 200, let data else { return nil }
                return try? WeatherReading.decode(data)
            }()
            DispatchQueue.main.async {
                guard let self, self.generation == version else { return }
                self.task = nil
                if let value {
                    self.reading = value
                    if let data = try? JSONEncoder().encode(value) { LocationSettings.storage.set(data, forKey: self.cacheKey) }
                    self.onChange?(value)
                }
            }
        }
        task?.resume()
    }
    deinit { task?.cancel() }
}

struct PrayerTime: Codable {
    let name: String
    let date: Date

    func line(now: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "h:mm a"
        let totalMinutes = max(0, Int(ceil(date.timeIntervalSince(now) / 60)))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        let countdown = "\(hours) \(hours == 1 ? "hour" : "hours") \(minutes) \(minutes == 1 ? "minute" : "minutes")"
        return "\(name.uppercased()) at \(formatter.string(from: date)) • \(countdown)"
    }

    static func next(in times: [PrayerTime], now: Date) -> PrayerTime? {
        times.filter { $0.date > now }.min { $0.date < $1.date }
    }
}

struct PrayerDay: Codable {
    let key: String
    let times: [PrayerTime]

    static func key(for date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "dd-MM-yyyy"
        return formatter.string(from: date)
    }

    static func decode(_ data: Data) throws -> PrayerDay {
        struct Response: Decodable {
            struct Day: Decodable {
                struct DayDate: Decodable {
                    struct Gregorian: Decodable { let date: String }
                    let gregorian: Gregorian
                }
                let timings: [String: String]
                let date: DayDate
            }
            let code: Int
            let data: Day
        }
        let response = try JSONDecoder().decode(Response.self, from: data)
        let parser = ISO8601DateFormatter()
        let names = ["Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"]
        let times = names.compactMap { name -> PrayerTime? in
            guard let value = response.data.timings[name], let date = parser.date(from: value) else { return nil }
            return PrayerTime(name: name, date: date)
        }
        guard response.code == 200, times.count == names.count else {
            throw CocoaError(.coderReadCorrupt)
        }
        return PrayerDay(key: response.data.date.gregorian.date, times: times)
    }
}

final class PrayerService {
    var onChange: (() -> Void)?
    private var settings = LocationSettings.load()
    private var timeZone = TimeZone.current
    private var days: [PrayerDay] = []
    private var tasks: [String: URLSessionDataTask] = [:]
    private var lastAttempts: [String: Date] = [:]
    private var generation = 0
    private var cacheKey: String { "prayers.isna.hanafi.\(settings.latitude).\(settings.longitude).\(timeZone.identifier)" }

    init() { loadCache() }
    private func loadCache() {
        days = LocationSettings.storage.data(forKey: cacheKey).flatMap {
            try? JSONDecoder().decode([PrayerDay].self, from: $0)
        } ?? []
    }
    func next(now: Date = Date()) -> PrayerTime? {
        guard days.contains(where: { $0.key == PrayerDay.key(for: now, timeZone: timeZone) }) else { return nil }
        return PrayerTime.next(in: days.flatMap(\.times), now: now)
    }
    func stop() {
        generation += 1
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
        lastAttempts.removeAll()
    }
    func reloadLocation() {
        stop(); settings = .load(); timeZone = .current; loadCache(); onChange?(); refresh()
    }
    func refresh(now: Date = Date()) {
        if timeZone.identifier != TimeZone.current.identifier { reloadLocation(); return }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) else { return }
        let keys = [now, tomorrow].map { PrayerDay.key(for: $0, timeZone: timeZone) }
        days.removeAll { !keys.contains($0.key) }
        for key in keys {
            guard !days.contains(where: { $0.key == key }), tasks[key] == nil,
                  now.timeIntervalSince(lastAttempts[key] ?? .distantPast) >= 300 else { continue }
            lastAttempts[key] = now
            let version = generation
            let url = Self.url(day: key, settings: settings, timeZone: timeZone)
            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
                let day: PrayerDay? = {
                    guard (response as? HTTPURLResponse)?.statusCode == 200, let data,
                          let value = try? PrayerDay.decode(data), value.key == key else { return nil }
                    return value
                }()
                DispatchQueue.main.async {
                    guard let self, self.generation == version else { return }
                    self.tasks.removeValue(forKey: key)
                    if let day {
                        self.days.removeAll { $0.key == key }
                        self.days.append(day)
                        if let data = try? JSONEncoder().encode(self.days) {
                            LocationSettings.storage.set(data, forKey: self.cacheKey)
                        }
                        self.onChange?()
                    }
                }
            }
            tasks[key] = task
            task.resume()
        }
    }
    static func url(day: String, settings: LocationSettings, timeZone: TimeZone) -> URL {
        var url = URLComponents(string: "https://api.aladhan.com/v1/timings/\(day)")!
        url.queryItems = [
            URLQueryItem(name: "latitude", value: String(settings.latitude)),
            URLQueryItem(name: "longitude", value: String(settings.longitude)),
            URLQueryItem(name: "method", value: "2"), // ISNA (North America)
            URLQueryItem(name: "school", value: "1"), // Hanafi Asr
            URLQueryItem(name: "iso8601", value: "true"),
            URLQueryItem(name: "timezonestring", value: timeZone.identifier)
        ]
        return url.url!
    }
    deinit { tasks.values.forEach { $0.cancel() } }
}
