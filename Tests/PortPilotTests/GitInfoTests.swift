import XCTest
@testable import PortManagerLib

/// detectGitInfo against synthetic repos in a temp directory — including the
/// worktree case (.git as a *file* pointing at the real gitdir).
final class GitInfoTests: XCTestCase {
    var detector: PortManager!
    var tmp: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        detector = PortManager()
        tmp = NSTemporaryDirectory() + "/portpilot-tests-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: tmp)
        try super.tearDownWithError()
    }

    private func makeRepo(name: String, head: String, config remoteURL: String? = nil) throws -> String {
        let repo = tmp + "/" + name
        let gitDir = repo + "/.git"
        try FileManager.default.createDirectory(atPath: gitDir, withIntermediateDirectories: true)
        try head.write(toFile: gitDir + "/HEAD", atomically: true, encoding: .utf8)
        if let remoteURL {
            try "[core]\n\trepositoryformatversion = 0\n[remote \"origin\"]\n\turl = \(remoteURL)\n"
                .write(toFile: gitDir + "/config", atomically: true, encoding: .utf8)
        }
        return repo
    }

    func testBranchFromHeadRef() throws {
        let repo = try makeRepo(
            name: "main-repo",
            head: "ref: refs/heads/feature/x\n",
            config: "git@github.com:sriinnu/portpilot.git"
        )
        let info = detector.detectGitInfo(for: repo)
        // The ref *path* carries the branch; the ref file's SHA must not leak.
        XCTAssertEqual(info.branch, "feature/x")
        XCTAssertEqual(info.repo, "sriinnu/portpilot")
    }

    func testDetachedHeadReturnsShortHash() throws {
        let repo = try makeRepo(name: "detached", head: "0123456789abcdef0123456789abcdef01234567\n")
        let info = detector.detectGitInfo(for: repo)
        XCTAssertEqual(info.branch, "0123456")
    }

    func testWorktreeDotGitFile() throws {
        let repo = try makeRepo(name: "wt-main", head: "ref: refs/heads/main\n", config: "git@github.com:sriinnu/portpilot.git")
        let worktreeGitDir = repo + "/.git/worktrees/wt1"
        try FileManager.default.createDirectory(atPath: worktreeGitDir, withIntermediateDirectories: true)
        try "ref: refs/heads/wt-branch\n".write(toFile: worktreeGitDir + "/HEAD", atomically: true, encoding: .utf8)

        let worktree = tmp + "/checkout-wt1"
        try FileManager.default.createDirectory(atPath: worktree, withIntermediateDirectories: true)
        try "gitdir: \(worktreeGitDir)\n".write(toFile: worktree + "/.git", atomically: true, encoding: .utf8)

        let info = detector.detectGitInfo(for: worktree)
        XCTAssertEqual(info.branch, "wt-branch")
        // The shared config lives two levels above the worktree gitdir
        // (/repo/.git/config vs /repo/.git/worktrees/wt) — resolving one
        // level short used to miss it.
        XCTAssertEqual(info.repo, "sriinnu/portpilot")
    }

    func testNoGitReturnsNils() {
        let info = detector.detectGitInfo(for: tmp)
        XCTAssertNil(info.branch)
        XCTAssertNil(info.repo)
        let empty = detector.detectGitInfo(for: nil)
        XCTAssertNil(empty.branch)
        XCTAssertNil(empty.repo)
    }

    func testRepoNameFromURLForms() {
        XCTAssertEqual(detector.extractRepoName(from: "git@github.com:sriinnu/portpilot.git"), "sriinnu/portpilot")
        XCTAssertEqual(detector.extractRepoName(from: "https://github.com/sriinnu/portpilot.git"), "sriinnu/portpilot")
        XCTAssertEqual(detector.extractRepoName(from: "git@github.com:sriinnu/portpilot"), "sriinnu/portpilot")
    }
}
