import SwiftUI
import Foundation

/// Policy and help are bundled for offline reading. Public website addresses
/// are readable text because native Watch web navigation is unavailable.
enum PublicInformation {
    static let privacyURL = URL(string: "https://fcw1987.github.io/PickleBlast/privacy/")!
    static let supportURL = URL(string: "https://fcw1987.github.io/PickleBlast/support/")!

    static var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        guard let version = info["CFBundleShortVersionString"] as? String,
              let build = info["CFBundleVersion"] as? String else { return "Version unavailable" }
        return "Version \(version) (build \(build))"
    }

    static let policyBlocks: [String] = {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        let url = bundle.url(forResource: "Privacy", withExtension: "txt", subdirectory: "Policy")
            ?? bundle.url(forResource: "Privacy", withExtension: "txt")
        guard let url, let text = try? String(contentsOf: url, encoding: .utf8), !text.isEmpty else {
            preconditionFailure("Missing bundled privacy policy. Run scripts/sync_privacy.py before building.")
        }
        return text.components(separatedBy: "\n\n").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
    }()
}

struct PrivacyView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Read this policy offline. No sign-in is needed.")
                    .font(.caption)
                    .accessibilityIdentifier("privacy.offline")
                WebsiteAddress(url: PublicInformation.privacyURL, identifier: "privacy")
                ForEach(Array(PublicInformation.policyBlocks.enumerated()), id: \.offset) { index, block in
                    if block.hasPrefix("# ") || block.hasPrefix("## ") {
                        Text(verbatim: String(block.dropFirst(block.hasPrefix("## ") ? 3 : 2)))
                            .font(.headline)
                            .fixedSize(horizontal: false, vertical: true)
                            .foregroundStyle(Neon.cyan)
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier("privacy.heading.\(index)")
                    } else {
                        Text(verbatim: block)
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("privacy.paragraph.\(index)")
                    }
                }
                Text("End of Privacy Policy")
                    .font(.caption)
                    .accessibilityIdentifier("privacy.end")
                Button("Back to Settings") { dismiss() }
                    .accessibilityIdentifier("privacy.back")
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .navigationTitle("Privacy")
        .background(Color.black)
        .accessibilityIdentifier("privacy.screen")
    }
}

struct SupportView: View {
    @Environment(\.dismiss) private var dismiss
    private let help: [(String, String, String)] = [
        ("Movement", "Turn the Digital Crown or drag across the court. Returns happen automatically when your player meets the incoming ball; you do not swing your wrist.", "movement"),
        ("Sensitivity", "In Settings, lower Crown sensitivity for finer movement or raise it for more movement per turn. Drag is also available.", "sensitivity"),
        ("Pause and resume", "Tap Pause at the top of the game. After an interruption, choose Resume and wait for the countdown. Home ends the current run; Restart begins it again.", "pause"),
        ("Haptics", "Check the Haptics switch in Settings. Feedback is paused when the app is inactive. Your Watch's system haptic settings can also affect what you feel.", "haptics"),
        ("Version and reports", "The app version and build appear above and in Settings. For a bug report, include them, your Watch model, watchOS version, what you did and what happened. A screenshot is optional; remove personal details.", "reports"),
        ("Public support", "The support website offers bug reports, feature requests and support questions through GitHub Issues. Posting requires a GitHub account and reports are public. Do not include passwords, account details, serial numbers or private logs.", "public")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Help is available offline.").font(.caption)
                    .accessibilityIdentifier("support.offline")
                Text(verbatim: PublicInformation.version).font(.caption.monospacedDigit())
                    .accessibilityIdentifier("support.version")
                WebsiteAddress(url: PublicInformation.supportURL, identifier: "support")
                ForEach(help.indices, id: \.self) { index in
                    let (title, body, identifier) = help[index]
                    Text(title).font(.headline).fixedSize(horizontal: false, vertical: true).foregroundStyle(Neon.cyan)
                        .accessibilityAddTraits(.isHeader)
                    Text(body).font(.callout).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("support.help.\(identifier)")
                }
                Button("Back to Settings") { dismiss() }
                    .accessibilityIdentifier("support.back")
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .navigationTitle("Support")
        .background(Color.black)
        .accessibilityIdentifier("support.screen")
    }
}

private struct WebsiteAddress: View {
    let url: URL
    let identifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: url.absoluteString)
                .font(.caption2)
                .foregroundStyle(Neon.cyan)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Website address: \(url.absoluteString)")
                .accessibilityIdentifier("\(identifier).url")
            Text("To visit the website, enter this address in a browser on another device. You can read the information here offline.")
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("\(identifier).fallback")
        }
    }
}
