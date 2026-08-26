import AppKit
import OpenPawCore
import SwiftUI

@MainActor
final class OnboardingPanelController {
    private var window: NSWindow?
    private var hosting: NSHostingView<OnboardingView>?

    /// Presents setup; calls `onComplete` with draft after Continue.
    /// Closing without Continue terminates the app.
    func present(draft: OnboardingDraft, onComplete: @escaping (OnboardingDraft) -> Void) {
        let binding = OnboardingViewModel(draft: draft)
        let view = OnboardingView(model: binding) { [weak self] finished in
            self?.window?.orderOut(nil)
            self?.window = nil
            self?.hosting = nil
            onComplete(finished)
        }
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 440, height: 620)

        // NSWindow (not NSPanel): agent apps + floating panels often never become
        // key/main, so the dock bounce shows nothing usable.
        let window = OnboardingWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 620),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Open Paw Setup"
        window.isReleasedWhenClosed = false
        window.backgroundColor = NSColor(red: 0.97, green: 0.97, blue: 0.98, alpha: 1)
        window.isOpaque = true
        window.hasShadow = true
        window.appearance = NSAppearance(named: .aqua)
        window.level = .floating
        window.collectionBehavior = [.moveToActiveSpace]
        window.contentView = host
        host.autoresizingMask = [.width, .height]
        window.delegate = CloseQuitsDelegate.shared
        window.center()

        self.window = window
        self.hosting = host
        bringToFront()
    }

    func bringToFront() {
        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.collectionBehavior.insert(.moveToActiveSpace)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}

/// Normal window that can become key + main (NSPanel defaults often block that).
private final class OnboardingWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class CloseQuitsDelegate: NSObject, NSWindowDelegate {
    static let shared = CloseQuitsDelegate()
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        NSApp.terminate(nil)
        return false
    }
}

@MainActor
final class OnboardingViewModel: ObservableObject {
    @Published var draft: OnboardingDraft

    init(draft: OnboardingDraft) {
        self.draft = draft
    }

    func harnessChanged(_ harness: HarnessKind) {
        draft.harness = harness
        draft.model = OnboardingOptions.defaultModel(for: harness)
    }
}

private enum OnboardTheme {
    // Light chrome so brand marks stay readable.
    static let bg = Color(red: 0.97, green: 0.97, blue: 0.98)
    static let card = Color.white
    static let stroke = Color.black.opacity(0.10)
    static let field = Color(red: 0.94, green: 0.94, blue: 0.96)
    static let label = Color.black.opacity(0.45)
    static let body = Color.black.opacity(0.88)
    static let purple = Color(red: 0.55, green: 0.28, blue: 0.92)
    static let orange = Color.orange
    static let selectFill = Color(red: 0.55, green: 0.28, blue: 0.92).opacity(0.10)
}

struct OnboardingView: View {
    @ObservedObject var model: OnboardingViewModel
    let onContinue: (OnboardingDraft) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                section("Agent") {
                    fieldLabel("Harness")
                    HarnessLogoPicker(
                        selection: Binding(
                            get: { model.draft.harness },
                            set: { model.harnessChanged($0) }
                        )
                    )

                    fieldLabel("Model")
                    menuPicker(selection: $model.draft.model) {
                        ForEach(OnboardingOptions.models(for: model.draft.harness), id: \.id) { m in
                            Text(m.label).tag(m.id)
                        }
                    }
                }

                section("Keys") {
                    fieldLabel("Gradium API key")
                    secureRow($model.draft.gradiumApiKey, placeholder: "gradium…")
                    if model.draft.harness == .hermes {
                        fieldLabel("Hermes API key")
                        secureRow($model.draft.hermesApiKey, placeholder: "matches API_SERVER_KEY")
                    }
                }

                if model.draft.harness == .claude {
                    section("Claude") {
                        fieldLabel("Permission mode")
                        menuPicker(selection: $model.draft.permissionMode) {
                            ForEach(OnboardingOptions.permissionModes, id: \.id) { m in
                                Text(m.label).tag(m.id)
                            }
                        }
                    }
                }

                if model.draft.harness == .claude || model.draft.harness == .codex {
                    section("Working directory") {
                        fieldLabel("cwd")
                        textRow($model.draft.cwd, placeholder: "~")
                    }
                }

                section("Hold to talk") {
                    fieldLabel("Key")
                    menuPicker(selection: $model.draft.holdKey) {
                        ForEach(OnboardingOptions.holdOptions, id: \.key) { opt in
                            Text(opt.recommended ? "\(opt.label) (recommended)" : opt.label)
                                .tag(opt.key)
                        }
                    }
                    Text("Recommended — keep this. Change only if that key is already used.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(OnboardTheme.label)
                }

                section("Buddy") {
                    fieldLabel("Position")
                    menuPicker(selection: $model.draft.buddyPosition) {
                        ForEach(OnboardingOptions.positions, id: \.id) { p in
                            Text(p.label).tag(p.id)
                        }
                    }
                }

                Button(action: { onContinue(model.draft) }) {
                    Text("Continue")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            LinearGradient(
                                colors: [OnboardTheme.purple, Color.purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: Capsule()
                        )
                        .shadow(color: Color.purple.opacity(0.45), radius: 12, y: 4)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
                .padding(.top, 4)
            }
            .padding(22)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(OnboardTheme.bg)
        .preferredColorScheme(.light)
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(nsImage: CatSprite.image(for: .idle))
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(width: 56, height: 56)
                .shadow(color: OnboardTheme.orange.opacity(0.35), radius: 10)
            VStack(alignment: .leading, spacing: 4) {
                Text("Open Paw")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(OnboardTheme.body)
                Text("Pick defaults once — then the cat is yours.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(OnboardTheme.label)
            }
            Spacer(minLength: 0)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(OnboardTheme.purple.opacity(0.9))
                .tracking(0.6)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OnboardTheme.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(OnboardTheme.stroke, lineWidth: 1))
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(OnboardTheme.label)
    }

    private func textRow(_ text: Binding<String>, placeholder: String) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(.system(size: 14, design: .rounded))
            .foregroundStyle(OnboardTheme.body)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(OnboardTheme.field, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(OnboardTheme.stroke, lineWidth: 1))
    }

    private func secureRow(_ text: Binding<String>, placeholder: String) -> some View {
        SecureField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(.system(size: 14, design: .rounded))
            .foregroundStyle(OnboardTheme.body)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(OnboardTheme.field, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(OnboardTheme.stroke, lineWidth: 1))
    }

    private func menuPicker<S: Hashable, Content: View>(
        selection: Binding<S>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Picker("", selection: selection, content: content)
            .labelsHidden()
            .pickerStyle(.menu)
            .tint(OnboardTheme.body)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(OnboardTheme.field, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(OnboardTheme.stroke, lineWidth: 1))
    }
}

/// Logo chips for Hermes / Claude / Codex — marks only; name via accessibility + help.
private struct HarnessLogoPicker: View {
    @Binding var selection: HarnessKind

    var body: some View {
        HStack(spacing: 6) {
            ForEach([HarnessKind.hermes, .claude, .codex], id: \.self) { kind in
                Button {
                    selection = kind
                } label: {
                    Image(nsImage: HarnessLogo.image(for: kind))
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: 32, height: 32)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            selection == kind
                                ? OnboardTheme.selectFill
                                : OnboardTheme.field,
                            in: RoundedRectangle(cornerRadius: 10)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(
                                    selection == kind
                                        ? OnboardTheme.purple.opacity(0.55)
                                        : OnboardTheme.stroke,
                                    lineWidth: 1
                                )
                        )
                }
                .buttonStyle(.plain)
                .help(kind.displayName)
                .accessibilityLabel(kind.displayName)
            }
        }
        .padding(4)
        .background(OnboardTheme.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(OnboardTheme.stroke, lineWidth: 1))
    }
}

/// Transparent brand marks from `@lobehub/icons-static` (MIT), rasterized to PNG.
private enum HarnessLogo {
    private static var cache: [HarnessKind: NSImage] = [:]

    static func image(for kind: HarnessKind) -> NSImage {
        if let cached = cache[kind] { return cached }
        let name: String
        switch kind {
        case .hermes: name = "harness_hermes"
        case .claude: name = "harness_claude"
        case .codex: name = "harness_codex"
        }
        let img = Bundle.module.url(forResource: name, withExtension: "png")
            .flatMap { NSImage(contentsOf: $0) }
            ?? NSImage(size: NSSize(width: 28, height: 28))
        cache[kind] = img
        return img
    }
}
