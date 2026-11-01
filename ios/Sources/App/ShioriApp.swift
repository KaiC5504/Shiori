import ShioriLibrary
import SwiftUI

@main
struct ShioriApp: App {
    @State private var model: AppModel?
    @State private var failure: String?

    init() {
        #if DEBUG
        // Simulator crash reports drop an Objective-C exception's reason, so it goes in a file in
        // the host's home folder, where CI's crash step prints it.
        NSSetUncaughtExceptionHandler { exception in
            let reason = "\(exception.name.rawValue): \(exception.reason ?? "no reason")\n"
            if let home = ProcessInfo.processInfo.environment["SIMULATOR_HOST_HOME"] {
                try? reason.write(toFile: home + "/shiori-exception.txt", atomically: true, encoding: .utf8)
            }
            fatalError(reason)
        }
        #endif
        do {
            _model = State(initialValue: try Self.makeModel())
        } catch {
            _failure = State(initialValue: String(describing: error))
        }
    }

    var body: some Scene {
        WindowGroup {
            if let model {
                RootView()
                    .environment(model)
                    .task {
                        #if DEBUG
                        await DemoLaunch.apply(to: model)
                        #endif
                        await model.scanOnLaunch()
                    }
            } else {
                LaunchFailureView(detail: failure ?? "")
            }
        }
    }

    private static func makeModel() throws -> AppModel {
        #if DEBUG
        if let demo = DemoLaunch.paths() {
            return try AppModel.live(paths: demo, defaults: DemoLaunch.defaults())
        }
        #endif
        return try AppModel.live(paths: .standard())
    }
}

/// Shown only if the library database can't be opened at all.
private struct LaunchFailureView: View {
    let detail: String

    var body: some View {
        VStack(spacing: 12) {
            Text("Shiori couldn't open its library.")
                .font(.headline)
            Text(verbatim: detail)
                .font(.footnote.monospaced())
                .foregroundStyle(Tokens.inkSecondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Tokens.paper.ignoresSafeArea())
    }
}
