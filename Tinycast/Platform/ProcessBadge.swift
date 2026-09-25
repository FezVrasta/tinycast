import Foundation

/// Names a spawned interpreter so Activity Monitor attributes it to Tinycast. The kernel sets
/// `p_comm` from the basename of the file it execs, and only a hard link changes it: a symlink
/// resolves first, and `process.title` rewrites argv, which Activity Monitor never reads.
enum ProcessBadge {
    /// `p_comm` is `MAXCOMLEN` bytes, and a truncated badge reads worse than none at all.
    static let nameLimit = 16

    /// The link, or the executable untouched when one can't be made. A badge is a convenience, so
    /// every failure falls back rather than throwing: refusing to launch over it is a worse trade.
    static func badged(_ executable: URL, in directory: URL? = nil) -> URL {
        let target = executable.resolvingSymlinksInPath()
        // A shebang script re-execs its interpreter, which overwrites the badge with `node`.
        guard !isScript(target) else { return executable }
        let name = badgeName(for: target)
        guard name.utf8.count <= nameLimit,
            let directory = directory ?? defaultDirectory(),
            (try? FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)) != nil
        else { return executable }

        let link = directory.appendingPathComponent(name)
        if sharesInode(link, target) { return link }
        // A node upgrade moves the inode, so a stale link would exec the interpreter it replaced.
        try? FileManager.default.removeItem(at: link)
        // Hard links can't cross volumes, and a version manager may sit on another one.
        guard (try? FileManager.default.linkItem(at: target, to: link)) != nil else {
            return executable
        }
        return link
    }

    static func badgeName(for executable: URL) -> String {
        "Tinycast (\(executable.lastPathComponent))"
    }

    static func isScript(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: 2)) == Data("#!".utf8)
    }

    private static func defaultDirectory() -> URL? {
        AppPaths.applicationSupport().appendingPathComponent("Processes")
    }

    private static func sharesInode(_ link: URL, _ target: URL) -> Bool {
        let keys: Set<URLResourceKey> = [.fileResourceIdentifierKey]
        guard let a = try? link.resourceValues(forKeys: keys).fileResourceIdentifier,
            let b = try? target.resourceValues(forKeys: keys).fileResourceIdentifier
        else { return false }
        return a.isEqual(b)
    }
}
