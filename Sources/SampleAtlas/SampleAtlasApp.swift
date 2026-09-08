import SwiftUI
import AppKit

@main
struct SampleAtlasApp: App {
    @StateObject private var model: AppModel
    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        do { let instance = try AppModel(); _model = StateObject(wrappedValue: instance) }
        catch {
            let alert = NSAlert(); alert.messageText = "Sample Atlas could not open its catalog"
            alert.informativeText = error.localizedDescription; alert.runModal()
            exit(1)
        }
    }
    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(model).frame(minWidth: 1060, minHeight: 700)
                .onAppear { NSApplication.shared.activate(ignoringOtherApps: true) }
        }
        .defaultSize(width: 1280, height: 820)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Add Sample Folders…") { model.addFolders() }.keyboardShortcut("o")
                Button("Rescan Library") { model.scan() }.keyboardShortcut("r").disabled(model.scanning)
            }
        }
    }
}
