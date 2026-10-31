import SwiftUI

struct RootView: View {
    var body: some View {
        ZStack {
            Color(red: 0xF2 / 255, green: 0xEC / 255, blue: 0xE3 / 255)
                .ignoresSafeArea()
            Text(verbatim: "Shiori")
                .font(.largeTitle.bold())
        }
    }
}
