import Foundation

/// The hard link that makes a spawned interpreter legible in Activity Monitor. `p_comm` comes from
/// the basename of the exec'd file, so the link's name is the whole mechanism.
@main
@MainActor
struct ProcessBadgeTests {
    static var failures = 0
    static var passes = 0

    static func check(_ label: String, _ ok: Bool) {
        if ok {
            passes += 1
        } else {
            failures += 1
            print("FAIL  \(label)")
        }
    }

    /// Two paths naming one file, which is what a hard link is.
    static func sameFile(_ a: URL, _ b: URL) -> Bool {
        let keys: Set<URLResourceKey> = [.fileResourceIdentifierKey]
        guard let x = try? a.resourceValues(forKeys: keys).fileResourceIdentifier as? NSObject,
            let y = try? b.resourceValues(forKeys: keys).fileResourceIdentifier as? NSObject
        else { return false }
        return x == y
    }

    static func main() {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("badge-\(UUID().uuidString)")
        let links = root.appendingPathComponent("Processes")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        // A real binary on the same volume, which is the case the badge exists for.
        let binary = root.appendingPathComponent("node")
        try? FileManager.default.copyItem(at: URL(fileURLWithPath: "/bin/echo"), to: binary)

        print("# a real binary gets a named hard link")
        let badged = ProcessBadge.badged(binary, in: links)
        check("the link is named for Tinycast", badged.lastPathComponent == "Tinycast (node)")
        check(
            "the link is in the badge directory",
            badged.deletingLastPathComponent().standardizedFileURL.path == links.standardizedFileURL.path)
        check("the link is the same file", sameFile(badged, binary))
        check("the name fits p_comm", badged.lastPathComponent.utf8.count <= ProcessBadge.nameLimit)

        print("\n# a second call reuses it")
        check("the same link comes back", ProcessBadge.badged(binary, in: links) == badged)

        print("\n# the link follows the interpreter")
        try? FileManager.default.removeItem(at: binary)
        try? FileManager.default.copyItem(at: URL(fileURLWithPath: "/bin/date"), to: binary)
        let remade = ProcessBadge.badged(binary, in: links)
        check("an upgraded interpreter is relinked", sameFile(remade, binary))

        print("\n# everything else is left alone")
        let script = root.appendingPathComponent("npm")
        try? Data("#!/bin/sh\necho hi\n".utf8).write(to: script)
        check(
            "a shebang script is not badged, since it re-execs its interpreter",
            ProcessBadge.badged(script, in: links) == script)

        let long = root.appendingPathComponent("interpreter-with-a-long-name")
        try? FileManager.default.copyItem(at: URL(fileURLWithPath: "/bin/echo"), to: long)
        check(
            "a name past the p_comm cap is not badged",
            ProcessBadge.badged(long, in: links) == long)

        let missing = root.appendingPathComponent("not-here")
        check("a path that isn't there is left alone", ProcessBadge.badged(missing, in: links) == missing)

        print("\n\(passes) passed, \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
