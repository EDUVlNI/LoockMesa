import Foundation

enum GergelimMigration {
    static func run(defaults: UserDefaults = .standard, readDomain: (String) -> [String: Any]? = { UserDefaults.standard.persistentDomain(forName: $0) }) {
        guard !defaults.bool(forKey: "Gergelim.imported.v1") else { return }
        for domain in ["com.eduvini.LoockMesa", "com.eduvini.lume"] {
            for (key, value) in readDomain(domain) ?? [:] where defaults.object(forKey: key) == nil {
                defaults.set(value, forKey: key)
            }
        }
        if let elements = defaults.stringArray(forKey: "ElementOrderV4") {
            defaults.set(elements.filter { $0 != "music" }, forKey: "ElementOrderV4")
        }
        defaults.set(true, forKey: "Gergelim.imported.v1")
    }
}
