//
//  ContentView.swift
//  01257057HW1
//
//  Created by user05 on 2025/9/18.
//

import SwiftUI
import AVFoundation
import Combine

enum RPS: String, CaseIterable, Identifiable {
    case 剪刀, 石頭, 布
    var id: String { rawValue }
    
    var symbolName: String {
        switch self {
        case .剪刀: return "scissors"
        case .石頭: return "cube"
        case .布:   return "doc"
        }
    }
    
    func result(against other: RPS) -> RoundResult {
        if self == other { return .draw }
        switch (self, other) {
        case (.剪刀, .布), (.石頭, .剪刀), (.布, .石頭):
            return .win
        default:
            return .lose
        }
    }
}

enum RoundResult {
    case win, lose, draw
}

// 三位角色與能力
enum Character: String, CaseIterable, Identifiable {
    case 強運戰士
    case 蓄力鬥士
    case 治療祭司
    
    var id: String { rawValue }
    
    var name: String {
        switch self {
        case .強運戰士: return "強運戰士"
        case .蓄力鬥士: return "蓄力鬥士"
        case .治療祭司: return "治療祭司"
        }
    }
    
    var description: String {
        switch self {
        case .強運戰士:
            return "猜贏時50%機率打出1.5×被動倍率的爆擊"
        case .蓄力鬥士:
            return "連續猜贏3次後，第4次打出2.5×被動倍率的爆發傷害"
        case .治療祭司:
            return "猜贏時回復本次造成傷害的50%（不影響護盾）"
        }
    }
    
    var icon: String {
        switch self {
        case .強運戰士: return "sparkles"
        case .蓄力鬥士: return "bolt.circle"
        case .治療祭司: return "cross.case"
        }
    }
}

// MARK: - Audio

final class AudioManager: ObservableObject {
    static let shared = AudioManager()
    
    private var players: [String: AVAudioPlayer] = [:]
    private let session = AVAudioSession.sharedInstance()
    
    private init() {
        try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true, options: [])
    }
    
    func preload(_ names: [String]) {
        for name in names {
            _ = player(for: name)
        }
    }
    
    private func player(for name: String) -> AVAudioPlayer? {
        if let cached = players[name] { return cached }
        guard let url = Bundle.main.url(forResource: name, withExtension: nil) else {
            return nil
        }
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.prepareToPlay()
            players[name] = p
            return p
        } catch {
            return nil
        }
    }
    
    func play(_ name: String, volume: Float = 1.0) {
        guard let p = player(for: name) else { return }
        p.currentTime = 0
        p.volume = volume
        p.play()
    }
}

// 統一音效鍵值（對應檔名）
private enum SFX {
    static let tap = "tap.mp3"
    static let attackNormal = "attack_normal.mp3"
    static let attackSpecial = "attack_special.mp3"
    static let win = "win.mp3"
    static let lose = "lose.mp3"
    static let enemyAttack = "attack_normal.mp3" // 可選，若沒有會自動無聲
}

struct ContentView: View {
    // MARK: - Main Menu State
    @State private var showMainMenu: Bool = true
    @State private var showAbout: Bool = false
    
    // MARK: - Meta progression (persistent)
    @AppStorage("tokens") private var tokens: Double = 0.0
    @AppStorage("talent1Level") private var talent1Level: Int = 0 // 攻擊力
    @AppStorage("talent2Level") private var talent2Level: Int = 0 // 防禦力
    @AppStorage("talent3Level") private var talent3Level: Int = 0 // 生命
    @AppStorage("talent4Level") private var talent4Level: Int = 0 // 角色被動倍率
    @AppStorage("talent5Level") private var talent5Level: Int = 0 // 無視防禦（最多5級）
    @AppStorage("talent6Level") private var talent6Level: Int = 0 // 護盾（最多100級）
    
    // MARK: - Run state
    @State private var playerHP: Int = 100
    @State private var playerMaxHP: Int = 100
    @State private var playerAttack: Int = 20
    @State private var playerDefense: Int = 10
    
    // 護盾
    @State private var playerShieldMax: Int = 0
    @State private var playerShield: Int = 0
    
    // CPU 基線屬性與當前戰鬥屬性
    @State private var cpuMaxHP: Int = 50
    @State private var cpuHP: Int = 50
    @State private var cpuAttack: Int = 5
    @State private var cpuDefense: Int = 0
    
    // Boss 回合控制
    @State private var isBossRound: Bool = false
    @State private var lastWinWasBoss: Bool = false
    @State private var bossWinsCount: Int = 0
    
    // 進度
    @State private var defeatCount: Int = 0
    
    // 回合顯示
    @State private var playerChoice: RPS? = nil
    @State private var cpuChoice: RPS? = nil
    @State private var message: String = "選擇你的出拳！"
    @State private var isGameOver: Bool = false
    @State private var shakePlayer: Bool = false
    @State private var shakeCPU: Bool = false
    
    // 角色相關
    @State private var selectedCharacter: Character? = nil
    @State private var winCountForChar2: Int = 0
    
    // Roguelike 升級（只在電腦血量歸零後出現）
    @State private var showUpgrade: Bool = false
    
    // 結算與天賦 UI
    @State private var showSettlement: Bool = false
    @State private var tokensEarnedThisRun: Double = 0.0
    @State private var showTalentsSheet: Bool = false
    
    // 數值設定
    private let baseCritMultiplier: Double = 1.5
    private let baseBurstMultiplier: Double = 2.5
    private let luckyCritChance: Double = 0.5
    
    // 被動倍率（由天賦4提供）
    @State private var passiveMultiplier: Double = 1.0
    
    // 計算用：天賦5 無視防禦（平坦值）
    private var ignoreDefenseFlat: Int {
        let lv = min(5, max(0, talent5Level))
        let base = lv * 5
        return lv >= 5 ? base + 25 : base // 5/10/15/20/50
    }
    
    // 護盾天賦提供的最大護盾
    private var computedShieldMax: Int {
        let lv = min(100, max(0, talent6Level))
        return lv * 5
    }
    
    // 目前被動倍率（用於選角畫面顯示）
    private var currentPassiveMultiplier: Double {
        var mult = 1.0 + 0.1 * Double(min(5, talent4Level))
        if talent4Level >= 5 { mult += 0.25 }
        return mult
    }
    
    // 依角色顯示總倍率字串
    private func totalPassiveLine(for character: Character) -> String {
        switch character {
        case .強運戰士:
            return String(format: "總倍率：爆擊 ×%.2f = 1.50 × %.2f", baseCritMultiplier * currentPassiveMultiplier, currentPassiveMultiplier)
        case .蓄力鬥士:
            return String(format: "總倍率：爆發 ×%.2f = 2.50 × %.2f", baseBurstMultiplier * currentPassiveMultiplier, currentPassiveMultiplier)
        case .治療祭司:
            let healBase = 0.5
            return String(format: "總倍率：治療 ×%.2f = 0.50 × %.2f", healBase * currentPassiveMultiplier, currentPassiveMultiplier)
        }
    }
    
    // MARK: - View
    var body: some View {
        ZStack {
            // Subtle animated gradient background
            LinearGradient(colors: [Color.blue.opacity(0.18), Color.purple.opacity(0.18)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
                .overlay(
                    RadialGradient(colors: [Color.white.opacity(0.08), .clear],
                                   center: .center, startRadius: 20, endRadius: 400)
                        .blur(radius: 40)
                )
                .overlay(
                    // Decorative faint circles
                    ZStack {
                        Circle()
                            .strokeBorder(Color.blue.opacity(0.12), lineWidth: 2)
                            .frame(width: 260, height: 260)
                            .blur(radius: 0.5)
                        Circle()
                            .strokeBorder(Color.purple.opacity(0.10), lineWidth: 2)
                            .frame(width: 360, height: 360)
                            .blur(radius: 0.5)
                    }
                )
            
            if showMainMenu {
                mainMenuView
            } else if selectedCharacter == nil {
                characterSelectionView
            } else {
                gameView
            }
            
            if showUpgrade {
                upgradeOverlay
            }
            
            if showSettlement {
                settlementOverlay
            }
        }
        .onAppear {
            // Preload sounds for minimal latency
            AudioManager.shared.preload([
                SFX.tap,
                SFX.attackNormal,
                SFX.attackSpecial,
                SFX.win,
                SFX.lose,
                SFX.enemyAttack
            ])
        }
        .animation(.easeInOut(duration: 0.25), value: playerHP)
        .animation(.easeInOut(duration: 0.25), value: cpuHP)
        .alert("遊戲結束", isPresented: $isGameOver) {
            Button("確定") { }
        } message: {
            Text("你被擊敗了，下次再挑戰！")
        }
        .sheet(isPresented: $showTalentsSheet) {
            TalentSheet(tokens: $tokens,
                        talent1Level: $talent1Level,
                        talent2Level: $talent2Level,
                        talent3Level: $talent3Level,
                        talent4Level: $talent4Level,
                        talent5Level: $talent5Level,
                        talent6Level: $talent6Level)
        }
        .sheet(isPresented: $showAbout) {
            AboutView {
                showAbout = false
            }
        }
    }
    
    // MARK: - Main Menu
    private var mainMenuView: some View {
        VStack(spacing: 28) {
            VStack(spacing: 8) {
                Text("我獨自猜拳")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .shadow(color: .black.opacity(0.15), radius: 3, x: 0, y: 2)
                Text("Rock · Paper · Scissors · Rogue")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 24)
            
            VStack(spacing: 16) {
                fancyMenuButton(title: "開始遊戲", systemImage: "play.circle.fill") {
                    AudioManager.shared.play(SFX.tap, volume: 0.8)
                    resetToCharacterSelect()
                    showMainMenu = false
                }
                fancyMenuButton(title: "天賦", systemImage: "star.circle.fill") {
                    AudioManager.shared.play(SFX.tap, volume: 0.8)
                    showTalentsSheet = true
                }
                fancyMenuButton(title: "關於", systemImage: "info.circle.fill") {
                    AudioManager.shared.play(SFX.tap, volume: 0.8)
                    showAbout = true
                }
            }
            .padding(.horizontal)
            
            VStack(spacing: 6) {
                Text("代幣：\(String(format: "%.2f", tokens))")
                    .font(.headline)
                Text("提示：可在遊戲中按「重置(回選角)」返回選角畫面")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 8)
            
            Spacer()
        }
        .padding(.vertical)
    }
    
    private func fancyMenuButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 26, weight: .bold))
                    .frame(width: 30)
                Text(title)
                    .font(.headline)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.accentColor.opacity(0.25), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }
    
    // MARK: - Character Selection
    private var characterSelectionView: some View {
        VStack(spacing: 24) {
            Text("選擇角色")
                .font(.largeTitle.bold())
                .padding(.top, 8)
            
            VStack(spacing: 16) {
                ForEach(Character.allCases) { character in
                    Button {
                        AudioManager.shared.play(SFX.tap, volume: 0.8)
                        choose(character)
                    } label: {
                        HStack(spacing: 16) {
                            Image(systemName: character.icon)
                                .font(.system(size: 28, weight: .bold))
                                .frame(width: 36)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(character.name)
                                    .font(.headline)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(character.description)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text(String(format: "當前被動倍率 ×%.2f", currentPassiveMultiplier))
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    Text(totalPassiveLine(for: character))
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(Color.accentColor.opacity(0.2), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
            }
            .padding(.horizontal)
            
            VStack(spacing: 8) {
                Text("代幣：\(String(format: "%.2f", tokens))")
                    .font(.headline)
                HStack(spacing: 12) {
                    Button {
                        AudioManager.shared.play(SFX.tap, volume: 0.8)
                        showTalentsSheet = true
                    } label: {
                        Label("前往天賦", systemImage: "star.circle")
                            .font(.headline)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Color.accentColor.opacity(0.2), in: Capsule())
                    }
                    .buttonStyle(ScaleButtonStyle())
                    
                    Button {
                        AudioManager.shared.play(SFX.tap, volume: 0.8)
                        selectedCharacter = nil
                        showMainMenu = true
                    } label: {
                        Label("返回主畫面", systemImage: "house")
                            .font(.headline)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Color.accentColor.opacity(0.15), in: Capsule())
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
            }
            .padding(.top, 4)
            
            Text("提示：可於遊戲中按「重置」返回選角畫面")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
        }
        .padding(.vertical)
    }
    
    // MARK: - Game View
    private var gameView: some View {
        VStack(spacing: 24) {
            Text("我獨自猜拳")
                .font(.largeTitle.bold())
                .padding(.top, 8)
            
            if let selectedCharacter {
                HStack(spacing: 8) {
                    Image(systemName: selectedCharacter.icon)
                    Text("角色：\(selectedCharacter.name)")
                        .font(.headline)
                    Spacer()
                    if selectedCharacter == .蓄力鬥士 {
                        Text("蓄力：\(winCountForChar2 % 4)/3")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .padding(.horizontal)
            }
            
            // 顯示玩家屬性與進度
            VStack(spacing: 6) {
                HStack(spacing: 16) {
                    Label("ATK \(playerAttack)", systemImage: "flame")
                    Label("DEF \(playerDefense)", systemImage: "shield")
                    Label("MAX \(playerMaxHP)", systemImage: "heart")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                
                HStack(spacing: 12) {
                    Label("SHD \(playerShield)/\(playerShieldMax)", systemImage: "shield.lefthalf.filled")
                    Label("敵擊敗 \(defeatCount)", systemImage: "trophy")
                    Label("Boss \(bossWinsCount)/10", systemImage: "crown")
                        .foregroundStyle(bossWinsCount >= 10 ? .green : (isBossRound ? .orange : .secondary))
                    if isBossRound {
                        Text("Boss 戰！")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(isBossRound ? .orange : .secondary)
            }
            .padding(.horizontal)
            
            // HP Bars
            VStack(spacing: 16) {
                hpRow(title: "玩家", hp: playerHP, maxHP: playerMaxHP, color: .green)
                    .modifier(Shake(animatableData: shakePlayer ? 1 : 0))
                hpRow(title: isBossRound ? "Boss" : "電腦",
                      hp: cpuHP,
                      maxHP: currentEnemyMaxHP,
                      color: isBossRound ? .orange : .red)
                    .modifier(Shake(animatableData: shakeCPU ? 1 : 0))
            }
            .padding(.horizontal)
            
            // Choices display
            HStack(spacing: 32) {
                choiceCard(owner: "玩家", choice: playerChoice)
                Image(systemName: "bolt.horizontal.fill")
                    .foregroundStyle(.secondary)
                choiceCard(owner: isBossRound ? "Boss" : "電腦", choice: cpuChoice)
            }
            
            // Message
            Text(message)
                .font(.title3.weight(.semibold))
                .padding(.horizontal)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .animation(.easeInOut, value: message)
            
            // Buttons
            HStack(spacing: 16) {
                ForEach(RPS.allCases) { rps in
                    Button {
                        AudioManager.shared.play(SFX.tap, volume: 0.6)
                        play(rps)
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: rps.symbolName)
                                .font(.system(size: 28, weight: .bold))
                            Text(rps.rawValue)
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .disabled(isGameOver || showUpgrade || showSettlement)
                }
            }
            .padding(.horizontal)
            
            // Reset
            HStack(spacing: 12) {
                Button {
                    AudioManager.shared.play(SFX.tap, volume: 0.8)
                    resetRoundOnly()
                } label: {
                    Text("重置回合")
                        .font(.headline)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                }
                .buttonStyle(ScaleButtonStyle())
                .disabled(showSettlement)
                Button {
                    AudioManager.shared.play(SFX.tap, volume: 0.8)
                    resetToCharacterSelect()
                } label: {
                    Text(isGameOver ? "再選角色" : "重置(回選角)")
                        .font(.headline)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.accentColor.opacity(0.25), in: Capsule())
                }
                .buttonStyle(ScaleButtonStyle())
                Button {
                    AudioManager.shared.play(SFX.tap, volume: 0.8)
                    showMainMenu = true
                    selectedCharacter = nil
                    resetGame()
                } label: {
                    Text("主畫面")
                        .font(.headline)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.accentColor.opacity(0.35), in: Capsule())
                }
                .buttonStyle(ScaleButtonStyle())
            }
            .padding(.bottom, 12)
        }
        .padding(.vertical)
    }
    
    // MARK: - Derived current enemy stats (Boss 取 2x)
    private var currentEnemyMaxHP: Int {
        isBossRound ? cpuMaxHP * 2 : cpuMaxHP
    }
    private var currentEnemyAttack: Int {
        isBossRound ? cpuAttack * 2 : cpuAttack
    }
    private var currentEnemyDefense: Int {
        let base = isBossRound ? cpuDefense * 2 : cpuDefense
        return max(0, base - ignoreDefenseFlat)
    }
    
    // MARK: - Upgrade Overlay
    private var upgradeOverlay: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 16) {
                Text(lastWinWasBoss ? "Boss 勝利！選擇雙倍強化" : "勝利！選擇一個強化")
                    .font(.title2.bold())
                VStack(spacing: 12) {
                    Button {
                        AudioManager.shared.play(SFX.tap, volume: 0.8)
                        applyUpgrade(.attack)
                    } label: {
                        if lastWinWasBoss {
                            upgradeCard(title: "攻擊力 +10", icon: "flame", subtitle: "Boss 獎勵：雙倍強化")
                        } else {
                            upgradeCard(title: "攻擊力 +5", icon: "flame", subtitle: "提升造成的傷害")
                        }
                    }
                    .buttonStyle(ScaleButtonStyle())
                    Button {
                        AudioManager.shared.play(SFX.tap, volume: 0.8)
                        applyUpgrade(.defense)
                    } label: {
                        if lastWinWasBoss {
                            upgradeCard(title: "防禦力 +6", icon: "shield", subtitle: "Boss 獎勵：雙倍強化")
                        } else {
                            upgradeCard(title: "防禦力 +3", icon: "shield", subtitle: "減少受到的傷害")
                        }
                    }
                    .buttonStyle(ScaleButtonStyle())
                    Button {
                        AudioManager.shared.play(SFX.tap, volume: 0.8)
                        applyUpgrade(.maxHP)
                    } label: {
                        if lastWinWasBoss {
                            upgradeCard(title: "血量上限 +40，並回復 60 生命", icon: "heart", subtitle: "上限提升且立即回復（不影響護盾）")
                        } else {
                            upgradeCard(title: "血量上限 +20，並回復 30 生命", icon: "heart", subtitle: "上限提升且立即回復（不影響護盾）")
                        }
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
                .padding(.horizontal)
            }
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .padding(24)
        }
        .transition(.opacity.combined(with: .scale))
    }
    
    // MARK: - Settlement Overlay
    private var settlementOverlay: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(spacing: 16) {
                Text("結算")
                    .font(.largeTitle.bold())
                VStack(spacing: 8) {
                    Label("一般擊敗：\(defeatCount)", systemImage: "trophy")
                    Label("Boss 擊敗：\(bossWinsCount)", systemImage: "crown")
                    Label("獲得代幣：\(String(format: "%.2f", tokensEarnedThisRun))", systemImage: "bitcoinsign.circle")
                }
                .font(.headline)
                .padding(.vertical, 4)
                
                HStack(spacing: 12) {
                    Button {
                        AudioManager.shared.play(SFX.tap, volume: 0.8)
                        tokens += tokensEarnedThisRun
                        tokensEarnedThisRun = 0
                        showSettlement = false
                        resetToCharacterSelect()
                        showMainMenu = true
                    } label: {
                        Text("領取並返回主畫面")
                            .font(.headline)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color.accentColor.opacity(0.25), in: Capsule())
                    }
                    .buttonStyle(ScaleButtonStyle())
                    Button {
                        AudioManager.shared.play(SFX.tap, volume: 0.8)
                        tokens += tokensEarnedThisRun
                        tokensEarnedThisRun = 0
                        showSettlement = false
                        resetToCharacterSelect()
                        showTalentsSheet = true
                    } label: {
                        Text("領取並前往天賦")
                            .font(.headline)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color.accentColor.opacity(0.35), in: Capsule())
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
            }
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .padding(24)
        }
        .transition(.opacity.combined(with: .scale))
    }
    
    private enum Upgrade {
        case attack, defense, maxHP
    }
    
    private func upgradeCard(title: String, icon: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .bold))
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
    
    // MARK: - UI Parts
    private func hpRow(title: String, hp: Int, maxHP: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Text("\(max(0, hp))/\(maxHP)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: Double(max(0, hp)), total: Double(maxHP))
                .tint(color)
                .shadow(color: color.opacity(0.35), radius: 4, x: 0, y: 2)
        }
    }
    
    private func choiceCard(owner: String, choice: RPS?) -> some View {
        VStack(spacing: 8) {
            Text(owner)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .frame(width: 110, height: 110)
                if let choice {
                    VStack(spacing: 6) {
                        Image(systemName: choice.symbolName)
                            .font(.system(size: 34, weight: .bold))
                        Text(choice.rawValue)
                            .font(.headline)
                    }
                } else {
                    Text("？")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
    
    // MARK: - Game Logic
    private func play(_ player: RPS) {
        guard !isGameOver, !showUpgrade, !showSettlement, let selectedCharacter else { return }
        playerChoice = player
        let cpu = RPS.allCases.randomElement() ?? .石頭
        cpuChoice = cpu
        
        let round = player.result(against: cpu)
        switch round {
        case .win:
            var damage = Double(playerAttack)
            var extraMsg: [String] = []
            var isSpecialAttack = false
            
            switch selectedCharacter {
            case .強運戰士:
                if Double.random(in: 0...1) < luckyCritChance {
                    damage *= (baseCritMultiplier * passiveMultiplier)
                    isSpecialAttack = true
                    extraMsg.append("觸發強運！造成\(String(format: "%.2f", baseCritMultiplier * passiveMultiplier))倍傷害")
                }
            case .蓄力鬥士:
                winCountForChar2 += 1
                if winCountForChar2 % 4 == 0 {
                    damage *= (baseBurstMultiplier * passiveMultiplier)
                    isSpecialAttack = true
                    extraMsg.append("蓄力爆發！造成\(String(format: "%.2f", baseBurstMultiplier * passiveMultiplier))倍傷害")
                } else {
                    let need = 4 - (winCountForChar2 % 4)
                    extraMsg.append("蓄力中：再贏\(need)次可觸發爆發")
                }
            case .治療祭司:
                break
            }
            
            let outgoing = max(1, Int(damage.rounded()) - currentEnemyDefense)
            cpuHP = max(0, cpuHP - outgoing)
            
            // 播放攻擊音效（特殊/普通）
            AudioManager.shared.play(isSpecialAttack ? SFX.attackSpecial : SFX.attackNormal, volume: 0.9)
            
            var baseMsg = "你贏了！對手受到 \(outgoing) 傷害。"
            if selectedCharacter == .治療祭司 {
                let healAmount = outgoing / 2
                let before = playerHP
                playerHP = min(playerMaxHP, playerHP + healAmount)
                let healed = playerHP - before
                if healed > 0 {
                    extraMsg.append("治療效果！回復\(healed)點生命")
                }
            }
            if !extraMsg.isEmpty {
                baseMsg += " " + extraMsg.joined(separator: "，")
            }
            message = baseMsg
            hitCPU()
            
            if cpuHP <= 0 {
                // 勝利時護盾回滿
                refillShield()
                // 勝利音效
                AudioManager.shared.play(SFX.win, volume: 1.0)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    handleEnemyDefeated()
                }
            }
            
        case .lose:
            let incomingRaw = max(1, currentEnemyAttack - playerDefense)
            let afterShield = applyDamageToShieldThenHP(incomingRaw)
            message = "你輸了！你受到 \(afterShield) 傷害。"
            // 敵方攻擊音效
            AudioManager.shared.play(SFX.enemyAttack, volume: 0.9)
            hitPlayer()
            
        case .draw:
            message = "平手！沒有造成傷害。"
        }
        
        if playerHP <= 0 {
            isGameOver = true
            tokensEarnedThisRun = calcTokenReward()
            showSettlement = true
            showUpgrade = false
            // 戰敗音效
            AudioManager.shared.play(SFX.lose, volume: 1.0)
        }
    }
    
    private func handleEnemyDefeated() {
        if isBossRound {
            bossWinsCount += 1
            if bossWinsCount >= 10 {
                tokensEarnedThisRun = calcTokenReward()
                showSettlement = true
                showUpgrade = false
                lastWinWasBoss = false
                message = "挑戰完成！"
                return
            }
            lastWinWasBoss = true
            message = "擊敗 Boss！選擇雙倍強化開始下一場"
            isBossRound = false
            showUpgrade = true
        } else {
            lastWinWasBoss = false
            message = "擊敗對手！選擇一個強化開始下一場"
            showUpgrade = true
            
            defeatCount += 1
            cpuMaxHP += 5
            if defeatCount % 5 == 0 {
                cpuAttack += 4
                cpuDefense += 5
            }
            if defeatCount % 10 == 0 {
                isBossRound = true
            }
        }
    }
    
    private func calcTokenReward() -> Double {
        return Double(defeatCount) + 5.0 * Double(bossWinsCount)
    }
    
    private func applyUpgrade(_ upgrade: Upgrade) {
        guard !showSettlement else { return }
        
        let atkGain = lastWinWasBoss ? 10 : 5
        let defGain = lastWinWasBoss ? 6 : 3
        let hpGain = lastWinWasBoss ? 40 : 20
        let healGain = lastWinWasBoss ? 60 : 30
        
        switch upgrade {
        case .attack:
            playerAttack += atkGain
            message = "升級成功！攻擊力 +\(atkGain)"
        case .defense:
            playerDefense += defGain
            message = "升級成功！防禦力 +\(defGain)"
        case .maxHP:
            playerMaxHP += hpGain
            let before = playerHP
            playerHP = min(playerMaxHP, playerHP + healGain)
            let healed = playerHP - before
            message = "升級成功！血量上限 +\(hpGain)；並回復 \(healed) 生命"
        }
        
        // 升級後開始新的一場
        showUpgrade = false
        lastWinWasBoss = false
        
        cpuHP = currentEnemyMaxHP
        cpuChoice = nil
        playerChoice = nil
        message += "，新的一場開始！"
    }
    
    private func resetRoundOnly() {
        playerHP = playerMaxHP
        playerShield = playerShieldMax
        cpuHP = currentEnemyMaxHP
        playerChoice = nil
        cpuChoice = nil
        message = "選擇你的出拳！"
        isGameOver = false
        showUpgrade = false
        lastWinWasBoss = false
    }
    
    private func resetToCharacterSelect() {
        resetGame()
        selectedCharacter = nil
        winCountForChar2 = 0
        playerAttack = 20 + talentAttackBonus()
        playerDefense = 10 + talentDefenseBonus()
        playerMaxHP = 100 + talentHPBonus()
        playerHP = playerMaxHP
        playerShieldMax = computedShieldMax
        playerShield = playerShieldMax
    }
    
    private func resetGame() {
        cpuHP = currentEnemyMaxHP
        playerChoice = nil
        cpuChoice = nil
        message = "選擇你的出拳！"
        isGameOver = false
        showUpgrade = false
        lastWinWasBoss = false
    }
    
    private func choose(_ character: Character) {
        selectedCharacter = character
        
        passiveMultiplier = 1.0 + 0.1 * Double(min(5, talent4Level))
        if talent4Level >= 5 {
            passiveMultiplier += 0.25
        }
        playerAttack = 20 + talentAttackBonus()
        playerDefense = 10 + talentDefenseBonus()
        playerMaxHP = 100 + talentHPBonus()
        playerHP = playerMaxHP
        
        playerShieldMax = computedShieldMax
        playerShield = playerShieldMax
        
        defeatCount = 0
        bossWinsCount = 0
        
        cpuMaxHP = 50
        cpuAttack = 5
        cpuDefense = 0
        isBossRound = false
        lastWinWasBoss = false
        
        cpuHP = currentEnemyMaxHP
        
        playerChoice = nil
        cpuChoice = nil
        message = "選擇你的出拳！"
        isGameOver = false
        winCountForChar2 = 0
        showUpgrade = false
        showSettlement = false
        tokensEarnedThisRun = 0
    }
    
    private func hitPlayer() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) {
            shakePlayer = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) {
                shakePlayer = false
            }
        }
    }
    
    private func hitCPU() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) {
            shakeCPU = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) {
                shakeCPU = false
            }
        }
    }
    
    private func applyDamageToShieldThenHP(_ damage: Int) -> Int {
        var remaining = damage
        if playerShield > 0 {
            let usedShield = min(playerShield, remaining)
            playerShield -= usedShield
            remaining -= usedShield
        }
        if remaining > 0 {
            let before = playerHP
            playerHP = max(0, playerHP - remaining)
            return before - playerHP
        } else {
            return 0
        }
    }
    
    private func refillShield() {
        playerShield = playerShieldMax
    }
    
    private func talentAttackBonus() -> Int {
        let lv = min(5, max(0, talent1Level))
        let base = lv * 5
        return lv >= 5 ? base + 25 : base
    }
    private func talentDefenseBonus() -> Int {
        let lv = min(5, max(0, talent2Level))
        let base = lv * 5
        return lv >= 5 ? base + 25 : base
    }
    private func talentHPBonus() -> Int {
        let lv = min(5, max(0, talent3Level))
        let base = lv * 10
        return lv >= 5 ? base + 50 : base
    }
}

// MARK: - Button scale style for nicer tap feedback
struct ScaleButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.96
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - About View
struct AboutView: View {
    var onClose: (() -> Void)?
    
    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 12) {
                Text("關於本遊戲")
                    .font(.title2.bold())
                Text("一款結合猜拳與 Roguelike 要素的休閒小遊戲。透過擊敗敵人獲得強化，挑戰 Boss，累積代幣以在天賦中升級。")
                    .font(.body)
                VStack(alignment: .leading, spacing: 6) {
                    Label("版本 1.0", systemImage: "number")
                    Label("作者 user05", systemImage: "person.crop.circle")
                    Label("平台 iOS", systemImage: "iphone")
                }
                .foregroundStyle(.secondary)
                Spacer()
            }
            .padding()
            .navigationTitle("關於")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("關閉") { onClose?() }
                }
            }
        }
    }
}

struct Shake: GeometryEffect {
    var amount: CGFloat = 8
    var shakesPerUnit: CGFloat = 3
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        let translation = amount * sin(animatableData * .pi * shakesPerUnit)
        return ProjectionTransform(CGAffineTransform(translationX: translation, y: 0))
    }
}

struct TalentSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    @Binding var tokens: Double
    @Binding var talent1Level: Int
    @Binding var talent2Level: Int
    @Binding var talent3Level: Int
    @Binding var talent4Level: Int
    @Binding var talent5Level: Int
    @Binding var talent6Level: Int
    
    private func costFor(level: Int) -> Double {
        switch level {
        case 0: return 5
        case 1: return 10
        case 2: return 15
        case 3: return 20
        case 4: return 25
        default: return .infinity
        }
    }
    
    private func canUpgrade(level: Int) -> Bool {
        level < 5 && tokens + 1e-9 >= costFor(level: level)
    }
    
    // 護盾成本：每升 1 級，成本 +2（升到 Lv.(n+1) 的成本 = 2*(n+1)）
    private func shieldCostFor(level: Int) -> Double {
        let nextLevel = level + 1
        return Double(2 * nextLevel)
    }
    
    private func canUpgradeShield(level: Int) -> Bool {
        guard level < 100 else { return false }
        let cost = shieldCostFor(level: level)
        return tokens + 1e-9 >= cost
    }
    
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("代幣：\(String(format: "%.2f", tokens))")) {
                    EmptyView()
                }
                
                talentRow(
                    title: "攻擊力",
                    desc: "每級 +5；5級額外 +25（最多5級）",
                    level: $talent1Level,
                    computePreview: { lv in
                        let base = lv * 5 + (lv >= 5 ? 25 : 0)
                        return "+\(base) ATK"
                    },
                    maxLevel: 5,
                    costProvider: costFor(level:),
                    canUpgrade: canUpgrade(level:),
                    onUpgrade: { lv, cost in
                        tokens -= cost
                        return min(5, lv + 1)
                    }
                )
                
                talentRow(
                    title: "防禦力",
                    desc: "每級 +5；5級額外 +25（最多5級）",
                    level: $talent2Level,
                    computePreview: { lv in
                        let base = lv * 5 + (lv >= 5 ? 25 : 0)
                        return "+\(base) DEF"
                    },
                    maxLevel: 5,
                    costProvider: costFor(level:),
                    canUpgrade: canUpgrade(level:),
                    onUpgrade: { lv, cost in
                        tokens -= cost
                        return min(5, lv + 1)
                    }
                )
                
                talentRow(
                    title: "生命",
                    desc: "每級 +10；5級額外 +50（最多5級）",
                    level: $talent3Level,
                    computePreview: { lv in
                        let base = lv * 10 + (lv >= 5 ? 50 : 0)
                        return "+\(base) MAX HP"
                    },
                    maxLevel: 5,
                    costProvider: costFor(level:),
                    canUpgrade: canUpgrade(level:),
                    onUpgrade: { lv, cost in
                        tokens -= cost
                        return min(5, lv + 1)
                    }
                )
                
                talentRow(
                    title: "角色被動倍率",
                    desc: "每級 +10% 倍率；5級額外 +0.25（最多5級）",
                    level: $talent4Level,
                    computePreview: { lv in
                        var mult = 1.0 + 0.1 * Double(min(5, lv))
                        if lv >= 5 { mult += 0.25 }
                        return String(format: "×%.2f 被動倍率", mult)
                    },
                    maxLevel: 5,
                    costProvider: costFor(level:),
                    canUpgrade: canUpgrade(level:),
                    onUpgrade: { lv, cost in
                        tokens -= cost
                        return min(5, lv + 1)
                    }
                )
                
                talentRow(
                    title: "無視防禦",
                    desc: "每級 +5 平坦無視；5級額外 +25（最多5級）",
                    level: $talent5Level,
                    computePreview: { lv in
                        let base = lv * 5 + (lv >= 5 ? 25 : 0)
                        return "無視防禦 \(base)"
                    },
                    maxLevel: 5,
                    costProvider: costFor(level:),
                    canUpgrade: canUpgrade(level:),
                    onUpgrade: { lv, cost in
                        tokens -= cost
                        return min(5, lv + 1)
                    }
                )
                
                // Talent 6: 護盾（最多100級，每級+5；成本每級 +2）
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("護盾")
                            .font(.headline)
                        Text("每級 +5 護盾，最多100級；只能靠天賦提升，勝利時自動回滿；無法被治療或能力值回復")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Max SHD +\(talent6Level * 5)")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(spacing: 6) {
                        Text("Lv. \(talent6Level)/100")
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                        Button {
                            guard canUpgradeShield(level: talent6Level) else { return }
                            let cost = shieldCostFor(level: talent6Level)
                            tokens -= cost
                            talent6Level = min(100, talent6Level + 1)
                        } label: {
                            if talent6Level >= 100 {
                                Text("已滿級")
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color.gray.opacity(0.2), in: Capsule())
                            } else {
                                let cost = shieldCostFor(level: talent6Level)
                                Text("升級(\(String(format: "%.1f", cost)))")
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(canUpgradeShield(level: talent6Level) ? Color.accentColor.opacity(0.25) : Color.gray.opacity(0.2), in: Capsule())
                            }
                        }
                        .disabled(!canUpgradeShield(level: talent6Level))
                    }
                }
                .padding(.vertical, 6)
            }
            .navigationTitle("天賦")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("關閉") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func talentRow(title: String,
                           desc: String,
                           level: Binding<Int>,
                           computePreview: @escaping (Int) -> String,
                           maxLevel: Int,
                           costProvider: @escaping (Int) -> Double,
                           canUpgrade: @escaping (Int) -> Bool,
                           onUpgrade: @escaping (Int, Double) -> Int) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(desc).font(.subheadline).foregroundStyle(.secondary)
                Text(computePreview(level.wrappedValue))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(spacing: 6) {
                Text("Lv. \(level.wrappedValue)/\(maxLevel)")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                Button {
                    AudioManager.shared.play(SFX.tap, volume: 0.8)
                    let lv = level.wrappedValue
                    let cost = costProvider(lv)
                    guard lv < maxLevel, tokens + 1e-9 >= cost else { return }
                    level.wrappedValue = onUpgrade(lv, cost)
                } label: {
                    if level.wrappedValue >= maxLevel {
                        Text("已滿級")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.gray.opacity(0.2), in: Capsule())
                    } else {
                        let cost = costProvider(level.wrappedValue)
                        Text("升級(\(String(format: "%.1f", cost)))")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background((canUpgrade(level.wrappedValue)) ? Color.accentColor.opacity(0.25) : Color.gray.opacity(0.2), in: Capsule())
                    }
                }
                .disabled(!canUpgrade(level.wrappedValue))
                .buttonStyle(ScaleButtonStyle())
            }
        }
        .padding(.vertical, 6)
    }
}

#Preview {
    ContentView()
}
