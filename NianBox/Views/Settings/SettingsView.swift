import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var loginItemService: LoginItemService
    @ObservedObject var syncEngine: SyncEngine
    @State private var serverURL = ""
    @State private var serverToken = ""
    @State private var configurationMessage: String?
    @ObservedObject var store: TaskStore

    var body: some View {
        // Scrolls when the window is shorter than the content (small screens,
        // extra sections like sync errors); the window caps its own height.
        ScrollView {
            content
        }
        .frame(width: 520)
        .onAppear {
            loginItemService.refresh()
            serverURL = syncEngine.configuredURL
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginItemService.refresh()
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 24) {
            header

            HStack(alignment: .top, spacing: 28) {
                CornerPicker(selection: $settings.corner)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Hiding corner")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text(settings.corner.title)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                    Text("The same corner works on every connected display.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("macOS Hot Corners may activate at the same time.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Quick capture shortcut", systemImage: "keyboard").font(.headline)
                    Spacer()
                    ShortcutRecorder(settings: settings).frame(width: 160, height: 28)
                }
                Text("Click the shortcut, then press your preferred keys. Escape cancels; Delete disables it.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Restore default shortcut") {
                    do { try settings.updateCaptureShortcut(.default) }
                    catch { settings.shortcutError = error.localizedDescription }
                }
                .controlSize(.small)
                if let error = settings.shortcutError {
                    Text(error).font(.caption).foregroundStyle(.orange)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Hide delay", systemImage: "eye.slash")
                        .font(.headline)
                    Spacer()
                    Text(settings.hideDelay, format: .number.precision(.fractionLength(1)))
                        .monospacedDigit()
                    Text("sec")
                        .foregroundStyle(.secondary)
                }
                Slider(value: $settings.hideDelay, in: 0.1...2.0, step: 0.1)
                Text("Wait this long after the cursor leaves before NianBox hides.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Reveal delay", systemImage: "timer")
                        .font(.headline)
                    Spacer()
                    Text(settings.revealDelay, format: .number.precision(.fractionLength(1)))
                        .monospacedDigit()
                    Text("sec")
                        .foregroundStyle(.secondary)
                }
                Slider(value: $settings.revealDelay, in: 0.2...2.0, step: 0.1)
                Text("Pause in the corner for this long before NianBox appears.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: $settings.isTranslucent) {
                    Label("Translucency", systemImage: "circle.lefthalf.filled")
                        .font(.headline)
                }
                Text("Let the desktop shine through the panel background.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: loginBinding) {
                    Label("Launch at login", systemImage: "power")
                        .font(.headline)
                }

                Text("Open NianBox automatically when you log in to this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if loginItemService.requiresApproval {
                    HStack {
                        Text("Approval is required in System Settings.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Button("Open Login Items") { loginItemService.openSystemSettings() }
                            .buttonStyle(.link)
                    }
                }

                if let error = loginItemService.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Divider()

            serverSection

            Divider()

            aboutFooter
        }
        .padding(28)
    }

    private var header: some View {
        HStack(spacing: 13) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text("NianBox")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text("A quiet list, right around the corner.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var loginBinding: Binding<Bool> {
        Binding(
            get: { loginItemService.isEnabled },
            set: { loginItemService.setEnabled($0) }
        )
    }

    private var serverSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("NianBox Server", systemImage: "arrow.triangle.2.circlepath")
                .font(.headline)
            Text(syncEngine.status).font(.caption).foregroundStyle(.secondary)
            TextField("https://nianbox.example.ts.net", text: $serverURL)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
            SecureField("API token (leave blank to keep saved token)", text: $serverToken)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("Save & sync") {
                    do {
                        try syncEngine.configure(url: serverURL, token: serverToken)
                        serverToken = ""
                        configurationMessage = nil
                    } catch { configurationMessage = error.localizedDescription }
                }
                .disabled(syncEngine.isSyncing)
                Button("Sync now") { syncEngine.requestSync() }
                Button("Work offline") { syncEngine.disable() }
            }
            if let configurationMessage {
                Text(configurationMessage).font(.caption).foregroundStyle(.orange)
            }
            if let lastSuccess = syncEngine.lastSuccess {
                Text("Last sync \(lastSuccess.formatted(date: .abbreviated, time: .standard))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Text("\(syncEngine.pendingCount) pending · \(syncEngine.blockedCount) retained conflicts")
                .font(.caption2).foregroundStyle(.secondary)
            Button("Export local data…") {
                let panel = NSSavePanel()
                panel.nameFieldStringValue = "nianbox-local-export.json"
                guard panel.runModal() == .OK, let url = panel.url else { return }
                do { try store.exportLocalData().write(to: url, options: .atomic) }
                catch { configurationMessage = "Could not export local data." }
            }
            .controlSize(.small)
            Text("Tasks are saved locally first. Hermes connects directly to this server, even while the Mac is off.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var aboutFooter: some View {
        VStack(spacing: 7) {
            Text("NianBox · Based on Peekaboo by Emanuele Di Pietro")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)

            Link(destination: URL(string: "https://github.com/takboo/nianbox")!) {
                Label("Open source on GitHub", systemImage: "arrow.up.right")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tertiary)
            .help("Open the NianBox repository")
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 2)
    }
}
