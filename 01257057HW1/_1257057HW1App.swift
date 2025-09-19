//
//  _1257057HW1App.swift
//  01257057HW1
//
//  Created by user05 on 2025/9/18.
//

import SwiftUI

@main
struct _1257057HW1App: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onChange(of: scenePhase) { _, newPhase in
                    switch newPhase {
                    case .active:
                        // 若有啟用 BGM 且已載入，就嘗試恢復播放
                        AudioManager.shared.playBGM(loop: true)
                    case .background, .inactive:
                        AudioManager.shared.pauseBGM()
                    @unknown default:
                        break
                    }
                }
        }
    }
}
