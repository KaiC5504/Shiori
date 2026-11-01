import ShioriLibrary
import SwiftUI

@main
struct ShioriApp: App {
    @State private var model: AppModel?
    @State private var failure: String?

    init() {
        #if DEBUG
        // Crash reports drop an Objective-C exception's reason; a fatal error's message is kept.
        NSSetUncaughtExceptionHandler { exception in
            fatalError("\(exception.name.rawValue): \(exception.reason ?? "no reason")")
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
