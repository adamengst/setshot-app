import Foundation

// Reports each Login Items & Extensions entry and whether it is allowed to run in the
// background. Invoked by setshot.sh as: SetShot --background-items
//
// Turning an item off in System Settings leaves its launchd plist in place, so the
// LAUNCH AGENTS & DAEMONS section cannot see the switch. It lives in the Background
// Task Management database, which `sfltool dumpbtm` reads only with admin approval.
// The database files themselves are world-readable and protected only by Full Disk
// Access, which SetShot already asks for, so they are read directly.
//
// The files are NSKeyedArchiver archives of private classes, decoded here by walking
// the archive's object table rather than by unarchiving, so an unknown class or a
// renamed field makes this print nothing instead of crashing. Silence sends the
// script back to its "not captured" line.
//
// Two layouts are known:
// - macOS 27 (v18): one file per user, BackgroundItems-v18-<user UUID>.btm, whose
//   root `userStore` holds `records`, an array of ItemRecord.
// - Earlier (v16 and before): one BackgroundItems-vN.btm whose root `store` holds
//   `itemsByUserIdentifier`, a dictionary from user UUID to that array.
// A Mac upgraded to 27 keeps its old v16 file, so the highest version wins.
enum BackgroundItems {
    static let directory = URL(fileURLWithPath: "/private/var/db/com.apple.backgroundtaskmanagement")

    /// `disposition` bit for the Login Items & Extensions switch. sfltool labels the
    /// bits enabled (0x1), allowed (0x2) and notified (0x8).
    static let allowedBit = 0x2

    /// `type` of a record that groups one developer's items (sfltool: "developer").
    static let developerType = 0x20

    /// The store BTM keeps for items that belong to the Mac rather than to a user:
    /// launch daemons such as an updater's privileged helper.
    static let systemStore = "FFFFEEEE-DDDD-CCCC-BBBB-AAAAFFFFFFFE"

    static func run() {
        guard let user = userUUID(),
              let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path)
        else { exit(0) }

        var lines: [String] = []
        for (store, domain) in [(user, "BTM"), (systemStore, "BTM-system")] {
            guard let (file, perUser) = databaseFile(among: names, user: store),
                  let data = try? Data(contentsOf: directory.appendingPathComponent(file))
            else { continue }
            lines += Self.lines(fromArchive: data, user: perUser ? nil : store, domain: domain)
        }
        if !lines.isEmpty {
            FileHandle.standardOutput.write(Data((lines.joined(separator: "\n") + "\n").utf8))
        }
        exit(0)
    }

    /// The file to read and whether it holds only this user's records.
    static func databaseFile(among names: [String], user: String) -> (String, Bool)? {
        var best: (version: Int, name: String, perUser: Bool)?
        for name in names where name.hasPrefix("BackgroundItems-v") && name.hasSuffix(".btm") {
            let stem = name.dropFirst("BackgroundItems-v".count).dropLast(".btm".count)
            let digits = stem.prefix(while: { $0.isNumber })
            guard let version = Int(digits) else { continue }
            let rest = stem.dropFirst(digits.count)
            let perUser: Bool
            if rest.isEmpty {
                perUser = false
            } else if rest.uppercased() == "-" + user {
                perUser = true
            } else {
                continue // another store's file
            }
            // Within one version the per-user file is the one with records; the bare
            // v18 file is only an index.
            if best == nil || version > best!.version
                || (version == best!.version && perUser && !best!.perUser) {
                best = (version, name, perUser)
            }
        }
        return best.map { ($0.name, $0.perUser) }
    }

    /// `<domain> :: <identifier> = 1 | 0` (allowed or not), sorted. Pass `user` for the
    /// older single-file layout, nil when the archive holds one store's records.
    static func lines(fromArchive data: Data, user: String?, domain: String = "BTM") -> [String] {
        guard let archive = Archive(data) else { return [] }

        let records: [Any]
        if let user {
            guard let store = archive.top("store").flatMap(archive.dict),
                  let byUser = store["itemsByUserIdentifier"].flatMap(archive.resolve)
                      .flatMap(archive.dictionary),
                  let mine = byUser.first(where: { key, _ in
                      (archive.resolve(key) as? String)?.uppercased() == user
                          || archive.uuidString(key) == user
                  })?.value,
                  let list = archive.resolve(mine).flatMap(archive.array)
            else { return [] }
            records = list
        } else {
            guard let store = archive.top("userStore").flatMap(archive.dict),
                  let list = store["records"].flatMap(archive.resolve).flatMap(archive.array)
            else { return [] }
            records = list
        }

        var allowed: [String: Bool] = [:]
        for ref in records {
            guard let record = archive.resolve(ref).flatMap(archive.dict),
                  archive.className(of: record) == "ItemRecord",
                  let identifier = record["identifier"].flatMap(archive.resolve) as? String,
                  let disposition = record["disposition"].flatMap(archive.resolve) as? Int
            else { continue }
            // A developer record groups that developer's items and keeps its own
            // disposition, which stays allowed after every item under it is turned
            // off. The items carry the switch, so the group would only contradict them.
            if record["type"].flatMap(archive.resolve) as? Int == developerType { continue }
            let key = itemKey(identifier)
            guard !key.isEmpty else { continue }
            // One switch can cover several records under the same bundle identifier
            // -- Acrobat has an app record and a type-8192 one -- and they move
            // together. It counts as allowed only while all of them are.
            allowed[key] = (allowed[key] ?? true) && disposition & allowedBit != 0
        }
        return allowed.keys.sorted().map { "\(domain) :: \($0) = \(allowed[$0]! ? 1 : 0)" }
    }

    /// BTM prefixes each identifier with its type number: "2.com.seriflabs.affinitydesigner2",
    /// "16.com.adobe.ARMDC.Communicator". Dropping it leaves a bundle identifier the
    /// comparison can name the app from, and folds an app's several records into one.
    static func itemKey(_ identifier: String) -> String {
        guard let dot = identifier.firstIndex(of: "."),
              !identifier[..<dot].isEmpty,
              identifier[..<dot].allSatisfy(\.isNumber)
        else { return identifier }
        return String(identifier[identifier.index(after: dot)...])
    }

    static func userUUID() -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/dsmemberutil")
        p.arguments = ["getuuid", "-u", String(getuid())]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let s = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return UUID(uuidString: s)?.uuidString
    }

    /// Read-only view of an NSKeyedArchiver object table.
    struct Archive {
        let objects: [Any]
        let topLevel: [String: Any]

        init?(_ data: Data) {
            guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
                  let root = plist as? [String: Any],
                  let objects = root["$objects"] as? [Any],
                  let top = root["$top"] as? [String: Any]
            else { return nil }
            self.objects = objects
            self.topLevel = top
        }

        func top(_ key: String) -> Any? { topLevel[key].flatMap(resolve) }

        /// Follows a UID reference into the table; anything else is already a value.
        func resolve(_ value: Any) -> Any? {
            guard let u = Archive.uid(value) else { return value }
            guard u < objects.count else { return nil }
            let target = objects[u]
            if let s = target as? String, s == "$null" { return nil }
            return target
        }

        func dict(_ value: Any) -> [String: Any]? { value as? [String: Any] }

        func className(of object: [String: Any]) -> String? {
            object["$class"].flatMap(resolve).flatMap(dict)?["$classname"] as? String
        }

        func array(_ value: Any) -> [Any]? {
            dict(value)?["NS.objects"] as? [Any]
        }

        func dictionary(_ value: Any) -> [(key: Any, value: Any)]? {
            guard let d = dict(value),
                  let keys = d["NS.keys"] as? [Any],
                  let values = d["NS.objects"] as? [Any],
                  keys.count == values.count else { return nil }
            return Array(zip(keys, values)).map { (key: $0.0, value: $0.1) }
        }

        /// A key archived as NSUUID rather than as a string.
        func uuidString(_ value: Any) -> String? {
            guard let d = resolve(value).flatMap(dict),
                  let bytes = d["NS.uuidbytes"] as? Data, bytes.count == 16 else { return nil }
            return bytes.withUnsafeBytes { NSUUID(uuidBytes: $0.bindMemory(to: UInt8.self).baseAddress) }
                .uuidString
        }

        /// The integer inside a CFKeyedArchiverUID, which Foundation exposes only as an
        /// opaque object whose description reads `<CFKeyedArchiverUID 0x…>{value = 12}`.
        static func uid(_ value: Any) -> Int? {
            let d = String(describing: value)
            guard d.hasPrefix("<CFKeyedArchiverUID"),
                  let r = d.range(of: "value = ") else { return nil }
            return Int(d[r.upperBound...].prefix(while: { $0.isNumber }))
        }
    }
}
