import SwiftUI

/// Local, read-only guidance. Opening help must not start monitoring or perform actions.
struct SecurityFAQView: View {
    @ObservedObject private var appSettings = AppSettings.shared
    @State private var search = ""

    private var query: String { search.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var visibleSections: [SecurityFAQSection] {
        SecurityFAQSection.all.compactMap { section in
            let entries = section.entries.filter {
                query.isEmpty || "\(section.title) \($0.question) \($0.answer)".localizedCaseInsensitiveContains(query)
            }
            return entries.isEmpty ? nil : SecurityFAQSection(title: section.title, entries: entries)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Security & precautions", systemImage: "shield.lefthalf.filled")
                .font(appSettings.appFont(size: 18, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            Text("PortPilot is a visibility and control tool, not a firewall, antivirus, or proof that a device is safe. Keep your existing protections enabled.")
                .font(appSettings.appFont(size: 12))
                .fixedSize(horizontal: false, vertical: true)
            TextField("Search security questions", text: $search)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Search security questions")
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if visibleSections.isEmpty {
                        Text("No matching questions. Try LAN, cron, alerts, or secrets.")
                            .foregroundColor(.secondary)
                    }
                    ForEach(visibleSections) { section in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(section.title)
                                .font(appSettings.appFont(size: 13, weight: .semibold))
                                .accessibilityAddTraits(.isHeader)
                            ForEach(section.entries) { entry in
                                SecurityFAQRow(entry: entry, searchQuery: query)
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.Surface.groupedFill)
                        .cornerRadius(10)
                    }
                }
                .font(appSettings.appFont(size: 12))
                .padding(.trailing, 4)
            }
        }
        .padding(16)
        .background(Theme.Surface.windowBackground)
    }
}

private struct SecurityFAQRow: View {
    let entry: SecurityFAQEntry
    let searchQuery: String
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            Text(entry.answer)
                .foregroundColor(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
        } label: {
            Text(entry.question)
                .fixedSize(horizontal: false, vertical: true)
        }
        .task(id: searchQuery) {
            if !searchQuery.isEmpty { expanded = true }
        }
    }
}

private struct SecurityFAQEntry: Identifiable {
    let question: String
    let answer: String
    var id: String { question }
}

private struct SecurityFAQSection: Identifiable {
    let title: String
    let entries: [SecurityFAQEntry]
    var id: String { title }

    // Keep this guidance aligned with AGENTS.md, mission.md, and the security assessment.
    static let all: [SecurityFAQSection] = [
        .init(title: "Before you act", entries: [
            .init(question: "What does Packet inspection capture?", answer: "Only an explicit macOS capture, bounded to 10 seconds or 200 packets, with a 128 KiB output buffer. The system tcpdump tool prints numeric endpoint and protocol summaries without payload display, capture files, or HTTPS decryption. Its 96-byte snapshots can contain initial payload bytes internally. Port filters are not PID attribution and can include other processes or transit traffic. It does not feed the threat detector or prove safety. Stop or close the capture panel to request cancellation. Existing capture-device permission is required; PortPilot does not elevate privileges or install a helper."),
            .init(question: "Should I run PortPilot as root or disable other protections?", answer: "No. Run the app and CLI as your normal user. Visibility can be limited by OS permissions; that is not a reason to give the entire tool root access. Keep your firewall, OS updates, and endpoint protections enabled. Passing source tests does not establish that an installed version is secure or replace independent protection."),
            .init(question: "What should I check before Kill or Freeze?", answer: "An alert is a reason to investigate, not proof of malware. Verify the current PID, executable path, user, and remote endpoint before acting; a PID or path is not a permanent identity. Cached actions recheck the captured process-start identity and refuse changed or unavailable identities. Refresh instead of bypassing that refusal. User-space checks still have a small check-to-signal race; they are not atomic kernel handles. Actions use your OS account, not a separate application login. Kill can escalate to SIGKILL and lose unsaved work. Freeze can leave sockets and locks held; resume from Ports. Do not target system or security processes just because they look unfamiliar."),
            .init(question: "Do Reserved ports or Guard prevent accidental kills?", answer: "Reserved ports show warnings; they do not prevent Kill or Freeze. Guard leaves current process incarnations alone when armed, then can terminate later holders on its configured ports. Review the ports and current processes first. Failed initial discovery must not arm an empty baseline; check errors and retry. Guard continues independently when threat monitoring is paused, and discovery failures can delay enforcement. Disarm invalidates pending enforcement checks, including escalation; already delivered signals cannot be undone, and the final check-to-signal race still exists. Disable guards separately; neither feature is a firewall or a guarantee of protection."),
            .init(question: "How do I know monitoring will start after login?", answer: "Check Launch at Login in Settings and its observed macOS status. Waiting for approval is not enabled; approve it in macOS Login Items if desired. A registration error or unavailable item means startup is not established. Test an installed copy after login separately; a local build and passing tests do not prove automatic startup. Threat monitoring and Guard have their own settings—review both.")
        ]),
        .init(title: "LAN & proxies", entries: [
            .init(question: "Does monitoring need a LAN listener?", answer: "No. Monitoring reads local OS connection snapshots. The optional TCP proxy is a separate feature and defaults to IPv4 loopback (127.0.0.1). Leave “Allow selected network clients” off unless another device genuinely needs to connect. The proxy is a byte relay, not remote access to the whole PortPilot app."),
            .init(question: "How should I allow a LAN client safely?", answer: "Use the narrowest actual client IP range: a single IPv4 client uses /32; a single IPv6 client uses /128. Never use 0.0.0.0/0 or ::/0 for local-only sharing. The opt-in listener is not restricted to one LAN interface: CIDRs filter the peer IP, and matching traffic can arrive through other interfaces or routes. Avoid router port forwarding and public exposure. Stop the proxy when finished and keep the target service's own access controls enabled."),
            .init(question: "Are CIDRs authentication or encryption?", answer: "No. A permitted source address is not a verified person or device, and a private LAN is not automatically trusted. The raw TCP relay adds no login or TLS. Shared subnets, DHCP address reuse, NAT, and VPN routes affect who can match. Use a target protocol with its own authentication and encryption; do not send plaintext credentials. Defaults limit each app Quick Proxy to 64 active connections and close idle connections after 300 seconds, but these bounds are not full denial-of-service protection."),
            .init(question: "Does the CLI proxy have the same controls as app Quick Proxy?", answer: "No. The CLI proxy command launches OpenSSH SOCKS forwarding using ssh -D. Its authentication, bind address, and lifetime depend on OpenSSH and your SSH configuration; it does not inherit app Quick Proxy's CIDR, connection-cap, or idle-timeout controls. Review that configuration separately. In app Quick Proxy, a custom CIDR policy also replaces the default loopback policy; include a loopback client explicitly if you still need it.")
        ]),
        .init(title: "Alerts & blind spots", entries: [
            .init(question: "Does adding a host to the alert list block its traffic?", answer: "No. The file and CLI call this a “blocklist”, but it only classifies connections for alerts. It does not install firewall rules, deny packets, or close existing connections. Existing matcher caches can take up to 60 seconds to refresh an edit. Enforce traffic policy with your firewall or the target service. Domains match the exact name and its subdomains; they are not resolved into IPs for matching. If a snapshot only contains an IP, add that IP or a supported range. Blocklist CIDR matching is IPv4-only; exact IPv6 addresses are supported."),
            .init(question: "What do Critical, Warning, and Info mean?", answer: "Critical means a remote matched your alert list. Warning means a connection-count, fan-out, or new-remote threshold was crossed. Info can mean a first-seen executable making several connections. Downloads, browsers, development tools, and shared services can trigger these rules legitimately. Review the evidence and tune thresholds carefully; a severity label is not a malware verdict."),
            .init(question: "Does “no findings” mean my machine is safe?", answer: "No. Detection uses periodic snapshots of established connections, not packet inspection or a complete attack log. Short-lived connections between polls, scans that never establish a connection, and processes hidden by OS permissions may be missed. A paused monitor, a pending first check, or a failing snapshot is not a clean bill of health. Check the status and latest findings instead of relying only on notifications."),
            .init(question: "Can the learning baseline be trusted as an allowlist?", answer: "No. New executable identities and remotes need repeated complete snapshots before promotion, while absolute alert-list and volume rules run from the first snapshot. Identity uses the user and executable path, with a PID-scoped fallback—not a signature or file hash. A replaced binary at the same path or persistent malicious behavior can still look familiar. Learning is in memory and resets when PortPilot quits or restarts, not when a monitored program restarts. It is not approval to trust a program."),
            .init(question: "Why did I get no banner, or why are findings stale?", answer: "Banners require PortPilot notifications and macOS permission. Repeated signals have a cooldown (15 minutes by default), and novel findings are combined into a summary. Muting banners does not stop tracking; turning Monitor off does. Snapshot failures keep the previous assessment without advancing learning, so displayed findings can be stale. Check the failure banner and retry Check now. Do not treat a command failure as zero connections.")
        ]),
        .init(title: "Cron, secrets & storage", entries: [
            .init(question: "What happens when I run or stop a cron job?", answer: "Run Now executes the selected command through /bin/sh with your user's permissions; it is not sandboxed. Inspect commands and scripts first, and test with harmless local jobs. Manual runs capture at most 256 KiB of output and time out after one hour. Stop and timeout attempt identity-checked descendant termination, but detached processes can escape. A failed, unknown or surviving target is not a confirmed stop—verify the result. The app's Stop also targets independently launched processes matching the command; review possible collateral targets. The manual-run limits do not govern OS-scheduled jobs. Pausing or resuming rewrites your real user crontab. Incomplete reads and detected concurrent edits are refused; another editor can still race after the final comparison. Review the resulting crontab and keep a backup before important edits."),
            .init(question: "Where is sensitive data stored, and what should I redact?", answer: "The alert list and threat history live under ~/.portpilot. Manual cron history is in Application Support/PortPilot and includes run metadata keyed by the full command. Captured output stays in memory, with excerpts in the live Activity Log; it is not stored in cron run history. Sensitive files use owner-only POSIX permissions (0600), with app-owned directories at 0700; this is not encryption, and your account, root, backups, or filesystem policy may still expose them. Keep secrets out of commands and output. Redact tokens, IPs, hostnames, usernames, paths, and job commands before sharing history, logs, screenshots, or bug reports."),
            .init(question: "Are these protections verified on Windows?", answer: "No. The native app and this validation target macOS. Some CLI paths support Linux, but Windows support is planned or partial. Do not assume macOS process signaling, cron behavior, Network.framework proxy policy, or POSIX file permissions provide equivalent protection on Windows; platform-specific implementation and tests are required.")
        ])
    ]
}
