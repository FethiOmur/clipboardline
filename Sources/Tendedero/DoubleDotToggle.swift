import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Decides when two presses of the period key count as the show/hide gesture.
/// Pure: it only sees "a key went down, it was or was not a period, at this
/// time", so it can be tested without an event stream.
struct DoubleDotDetector {
    /// The second period has to follow the first within this long.
    var interval: TimeInterval = 0.35
    /// The first period only counts if no other key was pressed this shortly
    /// before it. Periods typed in the flow of text ("cd ..", "wait...") are
    /// part of the text, not the gesture.
    var quietLeadIn: TimeInterval = 0.25

    private var firstDot: TimeInterval?
    private var lastTyping: TimeInterval = -.infinity

    /// Returns true when this key press completes the gesture.
    mutating func keyDown(isDot: Bool, at time: TimeInterval) -> Bool {
        guard isDot else {
            firstDot = nil
            lastTyping = time
            return false
        }
        if let first = firstDot, time - first < interval {
            // Done. Further periods right after this one are a run of dots,
            // not a second gesture.
            firstDot = nil
            lastTyping = time
            return true
        }
        if time - lastTyping >= quietLeadIn {
            firstDot = time
        } else {
            firstDot = nil
            lastTyping = time
        }
        return false
    }

    mutating func reset() {
        firstDot = nil
        lastTyping = -.infinity
    }
}

/// Shows and hides the line when the period key is pressed twice quickly,
/// from any app. It only listens: the periods still reach the app you are
/// typing in. Seeing keys pressed in other apps needs the Accessibility
/// permission; without it the gesture only works in this app's own windows.
/// macOS does not deliver key presses to listeners while a password field has
/// secure input on, and the detector is cleared then as well.
@MainActor
final class DoubleDotToggle {
    private static let defaultsKey = "doubleDotToggle"

    /// On unless switched off in Settings.
    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: defaultsKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: defaultsKey) }
    }

    private let action: () -> Void
    private var detector = DoubleDotDetector()
    private var monitors: [Any] = []
    private var trustedAtInstall = false
    private var activationObserver: NSObjectProtocol?

    init(action: @escaping () -> Void) {
        self.action = action
        // A global monitor added before the permission was granted may stay
        // deaf. Re-add it when the permission state has changed.
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.monitors.isEmpty, AXIsProcessTrusted() != self.trustedAtInstall else { return }
                self.sync()
            }
        }
        sync()
    }

    deinit {
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
    }

    /// Starts or stops listening to match the setting.
    func sync() {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors.removeAll()
        detector.reset()
        guard Self.isEnabled else { return }
        trustedAtInstall = AXIsProcessTrusted()
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }) { monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
            return event
        }) { monitors.append(local) }
    }

    private func handle(_ event: NSEvent) {
        if IsSecureEventInputEnabled() || ToggleShortcutRecorder.shared.isRecording {
            detector.reset()
            return
        }
        guard !event.isARepeat else { return }
        let isDot = event.characters == "."
            && event.modifierFlags.intersection([.command, .control, .option]).isEmpty
        if detector.keyDown(isDot: isDot, at: event.timestamp) { action() }
    }
}
