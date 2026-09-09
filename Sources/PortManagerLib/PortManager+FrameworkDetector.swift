import Foundation

// MARK: - Framework & Git Detection

extension PortManager {

    /// Detect framework type from working directory or process path
    public func detectFramework(for workingDirectory: String?, processPath: String? = nil) -> String? {
        if let framework = detectFrameworkInDirectory(workingDirectory) {
            return framework
        }
        if let path = processPath {
            let dir = (path as NSString).deletingLastPathComponent
            if let framework = detectFrameworkInDirectory(dir) {
                return framework
            }
            let parentDir = (dir as NSString).deletingLastPathComponent
            if let framework = detectFrameworkInDirectory(parentDir) {
                return framework
            }
        }
        return nil
    }

    /// Detect framework by scanning files in a directory
    func detectFrameworkInDirectory(_ dir: String?) -> String? {
        guard let dir = dir, !dir.isEmpty else { return nil }
        let fileManager = FileManager.default

        // Node.js ecosystem — parse package.json properly instead of substring
        // matching, so a stray "react" inside some unrelated string (or a
        // dependency that's only mentioned in a script) can't misclassify.
        let packageJSON = dir + "/package.json"
        if fileManager.fileExists(atPath: packageJSON) {
            if let content = try? String(contentsOfFile: packageJSON, encoding: .utf8),
               let data = content.data(using: .utf8),
               let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                func hasDep(_ name: String) -> Bool {
                    for section in ["dependencies", "devDependencies", "peerDependencies"] {
                        if let deps = json[section] as? [String: Any], deps[name] != nil { return true }
                    }
                    return false
                }
                if hasDep("next") { return "Next.js" }
                if hasDep("nuxt") { return "Nuxt" }
                if hasDep("@remix-run/react") || hasDep("remix") { return "Remix" }
                if hasDep("gatsby") { return "Gatsby" }
                if hasDep("astro") { return "Astro" }
                if hasDep("react") { return "React" }
                if hasDep("vue") { return "Vue" }
                if hasDep("svelte") { return "Svelte" }
                if hasDep("@angular/core") { return "Angular" }
                if hasDep("express") { return "Express" }
                if hasDep("fastify") { return "Fastify" }
                if hasDep("koa") { return "Koa" }
                return "Node.js"
            }
            return "Node.js"
        }

        // Python
        if fileManager.fileExists(atPath: dir + "/requirements.txt") { return "Python" }
        if fileManager.fileExists(atPath: dir + "/pyproject.toml") { return "Python" }
        if fileManager.fileExists(atPath: dir + "/Pipfile") { return "Python" }
        if fileManager.fileExists(atPath: dir + "/setup.py") { return "Python" }

        // Ruby/Rails
        if fileManager.fileExists(atPath: dir + "/Gemfile") {
            if fileManager.fileExists(atPath: dir + "/config.ru") { return "Rails" }
            return "Ruby"
        }

        // Go
        if fileManager.fileExists(atPath: dir + "/go.mod") { return "Go" }

        // Rust
        if fileManager.fileExists(atPath: dir + "/Cargo.toml") { return "Rust" }

        // Java
        if fileManager.fileExists(atPath: dir + "/pom.xml") { return "Java" }
        if fileManager.fileExists(atPath: dir + "/build.gradle") { return "Java" }
        if fileManager.fileExists(atPath: dir + "/build.gradle.kts") { return "Java" }

        // PHP/Composer
        if fileManager.fileExists(atPath: dir + "/composer.json") { return "PHP" }

        // .NET/C#
        if let entries = try? fileManager.contentsOfDirectory(atPath: dir),
           entries.contains(where: { $0.hasSuffix(".csproj") || $0.hasSuffix(".fsproj") || $0.hasSuffix(".vbproj") }) {
            return ".NET"
        }
        if fileManager.fileExists(atPath: dir + "/Program.cs") { return ".NET" }

        // Laravel specific
        if fileManager.fileExists(atPath: dir + "/artisan") { return "Laravel" }

        // Django
        if fileManager.fileExists(atPath: dir + "/manage.py") {
            if let content = try? String(contentsOfFile: dir + "/manage.py", encoding: .utf8),
               content.contains("django") { return "Django" }
        }

        return nil
    }

    // MARK: - Git Info Detection

    /// Resolves the real .git directory. In worktrees and submodules `.git` is
    /// a file containing "gitdir: <path>", not a directory.
    private func gitDirectory(for dir: String) -> String? {
        let dotGit = dir + "/.git"
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dotGit, isDirectory: &isDirectory) else {
            return nil
        }
        if isDirectory.boolValue { return dotGit }

        guard let content = try? String(contentsOfFile: dotGit, encoding: .utf8) else { return nil }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("gitdir:") else { return nil }
        let gitdir = String(trimmed.dropFirst("gitdir:".count)).trimmingCharacters(in: .whitespaces)
        return gitdir.isEmpty ? nil : gitdir
    }

    /// Detect git branch and repository from working directory
    public func detectGitInfo(for workingDirectory: String?) -> (branch: String?, repo: String?) {
        guard let dir = workingDirectory, !dir.isEmpty,
              let gitDir = gitDirectory(for: dir) else { return (nil, nil) }

        guard let headContent = try? String(contentsOfFile: gitDir + "/HEAD", encoding: .utf8) else {
            return (nil, nil)
        }

        let trimmed = headContent.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.starts(with: "ref: ") {
            // "ref: refs/heads/main" — the ref *path* carries the branch name.
            // The ref file's content is the commit SHA and must not be returned.
            // Strip the refs/heads/ prefix, keep the rest: "feature/x" is a
            // branch name, not a typo — lastPathComponent turned it into "x".
            let branchPath = String(trimmed.dropFirst(5))
            let branchName: String
            if branchPath.hasPrefix("refs/heads/") {
                branchName = String(branchPath.dropFirst("refs/heads/".count))
            } else if branchPath.hasPrefix("refs/") {
                branchName = String(branchPath.dropFirst("refs/".count))
            } else {
                branchName = branchPath
            }
            let repo = detectRepoName(from: dir)
            return (branchName, repo)
        }

        // Detached HEAD — the file contains the commit SHA directly.
        let shortHash = String(trimmed.prefix(7))
        let repo = detectRepoName(from: dir)
        return (shortHash, repo)
    }

    func detectRepoName(from workingDirectory: String) -> String? {
        var configPaths: [String] = []
        if let gitDir = gitDirectory(for: workingDirectory) {
            // Regular repo: /repo/.git/config. Linked worktree: gitDir
            // resolves to /repo/.git/worktrees/wt, so the shared config sits
            // two levels up — one deletion short used to miss it.
            configPaths.append(gitDir + "/config")
            let parent = (gitDir as NSString).deletingLastPathComponent
            configPaths.append(parent + "/config")
            configPaths.append((parent as NSString).deletingLastPathComponent + "/config")
        }
        configPaths.append(workingDirectory + "/.git/config")

        let config = configPaths.lazy.compactMap { try? String(contentsOfFile: $0, encoding: .utf8) }.first
        guard let config else {
            return nil
        }

        let lines = config.components(separatedBy: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("url = ") {
                let url = String(trimmed.dropFirst(6))
                if let name = extractRepoName(from: url) {
                    return name
                }
            }
        }
        return nil
    }

    func extractRepoName(from url: String) -> String? {
        var clean = url

        if clean.hasPrefix("https://") { clean = String(clean.dropFirst(8)) }
        else if clean.hasPrefix("http://") { clean = String(clean.dropFirst(7)) }
        else if clean.hasPrefix("git@") { clean = String(clean.dropFirst(4)) }

        if clean.hasSuffix(".git") {
            clean = String(clean.dropLast(4))
        }

        if clean.contains(":") {
            clean = clean.replacingOccurrences(of: ":", with: "/")
        }

        let parts = clean.split(separator: "/").map(String.init)
        if parts.count >= 2 {
            return parts.suffix(2).joined(separator: "/")
        } else if parts.count == 1 {
            return parts[0]
        }

        return nil
    }
}
