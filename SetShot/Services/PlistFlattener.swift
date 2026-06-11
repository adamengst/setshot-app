import Foundation

// Reads a plist from stdin (binary or XML), emits one "key = value" line per leaf.
// Invoked by setshot.sh as: SetShot --flatten-plist
// Matches the output format of the Python FLATTEN_PY that it replaces.
enum PlistFlattener {
    static func run() {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        guard !data.isEmpty,
              let obj = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        else { exit(1) }
        flatten(obj, prefix: "")
        exit(0)
    }

    static func flatten(_ obj: Any, prefix: String) {
        if let n = obj as? NSNumber {
            // CFBoolean check distinguishes a true bool from an integer 1/0.
            if CFGetTypeID(n as CFTypeRef) == CFBooleanGetTypeID() {
                print("\(prefix) = \(n.boolValue ? "True" : "False")")
            } else if let i = n as? Int, i == 0 || i == 1 {
                // Normalize integer 0/1 to False/True (matches Python behavior).
                print("\(prefix) = \(i == 1 ? "True" : "False")")
            } else if let i = n as? Int {
                print("\(prefix) = \(i)")
            } else {
                print("\(prefix) = \(n)")
            }
            return
        }

        switch obj {
        case let dict as [String: Any]:
            for key in dict.keys.sorted(by: <) {
                // Skip NSKeyedArchiver internal structure ($top, $objects, $archiver, $version).
                // These are object-graph indices, not settings, and change on every plist rewrite.
                guard !key.hasPrefix("$") else { continue }
                let p = prefix.isEmpty ? key : "\(prefix).\(key)"
                flatten(dict[key]!, prefix: p)
            }
        case let arr as [Any]:
            // Text replacement rules: each element is a dict with "replace" (trigger)
            // and "with" (expansion). Use the trigger as the key so that adding or
            // removing one entry doesn't cascade as changes to every subsequent index.
            if let dicts = arr as? [[String: Any]],
               !dicts.isEmpty,
               dicts.allSatisfy({ $0["replace"] is String && $0["with"] is String }) {
                for dict in dicts {
                    let trigger   = dict["replace"] as! String
                    let expansion = dict["with"]    as! String
                    let on        = (dict["on"] as? Bool) ?? true
                    let value     = on ? "\(trigger) → \(expansion)" : "\(trigger) → \(expansion) [off]"
                    print("\(prefix)[\(trigger)] = \(value)")
                }
            } else {
                for (i, val) in arr.enumerated() {
                    flatten(val, prefix: "\(prefix)[\(i)]")
                }
            }
        case let data as Data:
            // Try to interpret bytes as a nested plist before falling back.
            if let nested = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) {
                flatten(nested, prefix: prefix)
            } else {
                print("\(prefix) = <binary \(data.count) bytes>")
            }
        case let date as Date:
            let fmt = ISO8601DateFormatter()
            fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            print("\(prefix) = \(fmt.string(from: date))")
        case let str as String:
            let val = str.count > 300 ? String(str.prefix(300)) + "..." : str
            print("\(prefix) = \(val)")
        default:
            // UIDs and other opaque NSObject subclasses
            let typeName = String(describing: type(of: obj))
            if typeName.contains("UID"), let nsobj = obj as? NSObject,
               let val = nsobj.value(forKey: "value") {
                print("\(prefix) = <UID \(val)>")
            } else {
                let desc = "\(obj)"
                print("\(prefix) = \(desc.count > 300 ? String(desc.prefix(300)) + "..." : desc)")
            }
        }
    }
}
