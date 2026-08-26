import Foundation

// Reads a plist from stdin (binary or XML), emits one "key = value" line per leaf.
// Invoked by setshot.sh as: SetShot --flatten-plist
// Matches the output format of the Python FLATTEN_PY that it replaces.
//
// Batch mode (--flatten-plist-batch) reads a list of plist paths from stdin and
// emits "<path> :: key = value" for all of them in one invocation. The snapshot
// walks ~500 plists, and spawning this binary per file costs far more than the
// parsing does: every launch pulls in SwiftUI, AppKit, MusicKit and Sparkle to
// read a few kilobytes. Emitting the path prefix here also removes the per-file
// `sed` the script would otherwise need. Output is identical to the per-file
// path, so snapshots stay comparable across the change (SNAPSHOT_FORMAT is
// unaffected).
enum PlistFlattener {
    static func run() {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        guard !data.isEmpty,
              let obj = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        else { exit(1) }
        var out = ""
        flatten(obj, prefix: "", line: "", into: &out)
        emit(out)
        exit(0)
    }

    /// Reads newline-separated plist paths from stdin, flattens each in turn.
    /// A path that is missing, unreadable or unparseable contributes no lines,
    /// matching the per-file path where the shell redirect or the parse fails.
    static func runBatch() {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { exit(0) }
        var out = ""
        out.reserveCapacity(4 << 20)
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let path = String(line)
            guard let data = FileManager.default.contents(atPath: path), !data.isEmpty,
                  let obj = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
            else { continue }
            flatten(obj, prefix: "", line: "\(path) :: ", into: &out)
        }
        emit(out)
        exit(0)
    }

    private static func emit(_ out: String) {
        guard !out.isEmpty else { return }
        FileHandle.standardOutput.write(Data(out.utf8))
    }

    // `line` is prepended to every emitted line: empty in per-file mode, and
    // "<path> :: " in batch mode, where it replaces the script's `sed` prefix.
    static func flatten(_ obj: Any, prefix: String, line: String, into out: inout String) {
        if let n = obj as? NSNumber {
            // CFBoolean check distinguishes a true bool from an integer 1/0.
            if CFGetTypeID(n as CFTypeRef) == CFBooleanGetTypeID() {
                out += "\(line)\(prefix) = \(n.boolValue ? "True" : "False")\n"
            } else if let i = n as? Int, i == 0 || i == 1 {
                // Normalize integer 0/1 to False/True (matches Python behavior).
                out += "\(line)\(prefix) = \(i == 1 ? "True" : "False")\n"
            } else if let i = n as? Int {
                out += "\(line)\(prefix) = \(i)\n"
            } else {
                out += "\(line)\(prefix) = \(n)\n"
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
                flatten(dict[key]!, prefix: p, line: line, into: &out)
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
                    out += "\(line)\(prefix)[\(trigger)] = \(value)\n"
                }
            } else {
                for (i, val) in arr.enumerated() {
                    flatten(val, prefix: "\(prefix)[\(i)]", line: line, into: &out)
                }
            }
        case let data as Data:
            // Try to interpret bytes as a nested plist before falling back.
            if let nested = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) {
                flatten(nested, prefix: prefix, line: line, into: &out)
            } else {
                out += "\(line)\(prefix) = <binary \(data.count) bytes>\n"
            }
        case let date as Date:
            let fmt = ISO8601DateFormatter()
            fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            out += "\(line)\(prefix) = \(fmt.string(from: date))\n"
        case let str as String:
            let val = str.count > 300 ? String(str.prefix(300)) + "..." : str
            out += "\(line)\(prefix) = \(val)\n"
        default:
            // UIDs and other opaque NSObject subclasses
            let typeName = String(describing: type(of: obj))
            if typeName.contains("UID"), let nsobj = obj as? NSObject,
               let val = nsobj.value(forKey: "value") {
                out += "\(line)\(prefix) = <UID \(val)>\n"
            } else {
                let desc = "\(obj)"
                out += "\(line)\(prefix) = \(desc.count > 300 ? String(desc.prefix(300)) + "..." : desc)\n"
            }
        }
    }
}
