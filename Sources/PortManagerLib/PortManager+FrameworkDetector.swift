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

        // Node.js ecosystem
        let packageJSON = dir + "/package.json"
        if fileManager.fileExists(atPath: packageJSON) {
            if let content = try? String(contentsOfFile: packageJSON, encoding: .utf8) {
                if content.contains("\"next\"") { return "Next.js" }
                if content.contains("\"nuxt\"") { return "Nuxt" }
                if content.contains("\"remix\"") { return "Remix" }
                if content.contains("\"gatsby\"") { return "Gatsby" }
                if content.contains("\"astro\"") { return "Astro" }
                if content.contains("\"react\"") { return "React" }
                if content.contains("\"vue\"") && !content.contains("nuxt") { return "Vue" }
                if content.contains("\"svelte\"") { return "Svelte" }
                if content.contains("\"angular\"") { return "Angular" }
                if content.contains("\"express\"") { return "Express" }
                if content.contains("\"fastify\"") { return "Fastify" }
                if content.contains("\"koa\"") { return "Koa" }
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

    /// Detect git branch and repository from working directory
    public func detectGitInfo(for workingDirectory: String?) -> (branch: String?, repo: String?) {
        guard let dir = workingDirectory, !dir.isEmpty else { return (nil, nil) }

        let headFile = dir + "/.git/HEAD"
        guard let headContent = try? String(contentsOfFile: headFile, encoding: .utf8) else {
            return (nil, nil)
        }

        let trimmed = headContent.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.starts(with: "ref: ") {
            let branchPath = String(trimmed.dropFirst(5))

            let refFile = dir + "/.git/" + branchPath
            if let branchName = try? String(contentsOfFile: refFile, encoding: .utf8) {
                let trimmedBranch = branchName.trimmingCharacters(in: .whitespacesAndNewlines)
                let cleanBranch = trimmedBranch.components(separatedBy: "/").last ?? trimmedBranch
                let repo = detectRepoName(from: dir)
                return (cleanBranch, repo)
            }

            let branchName = branchPath.components(separatedBy: "/").last ?? branchPath
            let repo = detectRepoName(from: dir)
            return (branchName, repo)
        }

        let shortHash = String(trimmed.prefix(7))
        let repo = detectRepoName(from: dir)
        return (shortHash, repo)
    }

    func detectRepoName(from workingDirectory: String) -> String? {
        let configFile = workingDirectory + "/.git/config"
        guard let config = try? String(contentsOfFile: configFile, encoding: .utf8) else {
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
