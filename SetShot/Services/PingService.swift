import Foundation

enum PingService {
    private static let lastPingKey = "LastPingDate"
    private static let endpoint = URL(string: "https://setshot-submission.the-account-of-adam-engst.workers.dev/ping")!

    static func pingIfNeeded() {
        let today = Calendar.current.startOfDay(for: .now)
        if let last = UserDefaults.standard.object(forKey: lastPingKey) as? Date,
           Calendar.current.startOfDay(for: last) == today {
            return
        }

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let macos = ProcessInfo.processInfo.operatingSystemVersionString

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONEncoder().encode(["app_version": version, "macos_version": macos])

        URLSession.shared.dataTask(with: req) { _, response, _ in
            if (response as? HTTPURLResponse)?.statusCode == 200 {
                DispatchQueue.main.async {
                    UserDefaults.standard.set(Date.now, forKey: lastPingKey)
                }
            }
        }.resume()
    }
}
