import AppKit
import SwiftUI

struct PermissionsWindow: View {
    @State private var accessibilityTrusted = PermissionsProbe.isAccessibilityTrusted(prompt: false)

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(L10n.string("onboarding.title"), systemImage: "hand.raised")
                .font(.title2)

            Text(L10n.string("onboarding.body"))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Image(systemName: accessibilityTrusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(accessibilityTrusted ? .green : .orange)
                Text(accessibilityTrusted ? L10n.string("onboarding.axGranted") : L10n.string("onboarding.axMissing"))
            }

            HStack {
                Button(L10n.string("onboarding.openSettings")) {
                    _ = PermissionsProbe.isAccessibilityTrusted(prompt: true)
                    openPrivacySettings()
                }

                Button(L10n.string("onboarding.refresh")) {
                    accessibilityTrusted = PermissionsProbe.isAccessibilityTrusted(prompt: false)
                }
            }

            Spacer()
        }
        .padding(24)
    }

    private func openPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }

        NSWorkspace.shared.open(url)
    }
}
