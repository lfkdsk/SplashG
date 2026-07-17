import SwiftUI

struct RootView: View {
    @EnvironmentObject private var auth: AuthManager

    var body: some View {
        Group {
            if Config.demoRepo != nil {
                MainView()
            } else if auth.booting {
                ZStack {
                    Theme.bg.ignoresSafeArea()
                    VStack(spacing: 16) {
                        Image(systemName: "photo.stack")
                            .font(.system(size: 44, weight: .light))
                            .foregroundStyle(Theme.titleGradient)
                        Text("SplashG")
                            .font(.title2.bold())
                    }
                }
            } else if auth.token == nil {
                LoginView()
            } else {
                MainView()
            }
        }
        .task { await auth.boot() }
    }
}
