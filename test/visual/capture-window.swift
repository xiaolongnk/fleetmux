import AppKit
import Foundation
import ScreenCaptureKit

@main
struct CaptureWindow {
    static func main() async {
        guard CommandLine.arguments.count == 3,
              let wantedID = CGWindowID(CommandLine.arguments[1]) else {
            fputs("usage: capture-window.swift <window-id> <output.png>\n", stderr)
            exit(64)
        }

        do {
            _ = NSApplication.shared
            guard CGPreflightScreenCaptureAccess() else {
                fputs("capture FAILED: Screen Recording permission is not granted\n", stderr)
                exit(1)
            }
            let content = try await SCShareableContent.excludingDesktopWindows(
                true,
                onScreenWindowsOnly: true
            )
            guard let window = content.windows.first(where: { $0.windowID == wantedID }) else {
                fputs("capture FAILED: ScreenCaptureKit cannot see window id \(wantedID)\n", stderr)
                exit(1)
            }

            let filter = SCContentFilter(desktopIndependentWindow: window)
            let configuration = SCStreamConfiguration()
            configuration.width = max(1, Int(window.frame.width * 2))
            configuration.height = max(1, Int(window.frame.height * 2))
            configuration.showsCursor = false
            configuration.capturesAudio = false

            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
            let representation = NSBitmapImageRep(cgImage: image)
            guard let png = representation.representation(using: .png, properties: [:]) else {
                fputs("capture FAILED: could not encode PNG\n", stderr)
                exit(1)
            }
            try png.write(to: URL(fileURLWithPath: CommandLine.arguments[2]), options: .atomic)
        } catch {
            fputs("capture FAILED: \(error)\n", stderr)
            exit(1)
        }
    }
}
