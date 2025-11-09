import Foundation

struct WeatherConfiguration {
    let baseURL: URL
    let apiKey: String
}

enum WeatherConfigurationLoader {
    static func load() -> WeatherConfiguration? {
        guard let url = Bundle.main.url(forResource: "Weather", withExtension: "plist", subdirectory: "Config") ??
                Bundle.main.url(forResource: "Weather", withExtension: "plist") else {
            print("WeatherConfigurationLoader: Weather.plist が見つかりません")
            return nil
        }

        do {
            let data = try Data(contentsOf: url)
            guard
                let plist = try PropertyListSerialization.propertyList(
                    from: data,
                    options: [],
                    format: nil
                ) as? [String: Any],
                let baseURLString = plist["baseURL"] as? String,
                let apiKey = plist["apiKey"] as? String,
                let baseURL = URL(string: baseURLString),
                !apiKey.isEmpty
            else {
                print("WeatherConfigurationLoader: Weather.plist のフォーマットが不正です")
                return nil
            }
            return WeatherConfiguration(baseURL: baseURL, apiKey: apiKey)
        } catch {
            print("WeatherConfigurationLoader: 読み込みエラー \(error)")
            return nil
        }
    }
}
