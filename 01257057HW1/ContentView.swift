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
    
    // 僅保留能力敘述（移除「目前總倍率會等於…」）
    var description: String {
        switch self {
        case .強運戰士:
            return "猜贏時 50% 機率造成 1.50× 傷害"
        case .蓄力鬥士:
            return "連續猜贏 3 次後，第 4 次造成 2.50× 傷害"
        case .治療祭司:
            return "猜贏時回復本次造成傷害的 50%"
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
    private var bgmPlayer: AVAudioPlayer?
    private let session = AVAudioSession.sharedInstance()
    
    var bgmVolume: Float = 0.6 {
        didSet { bgmPlayer?.volume = bgmVolume }
    }
    var sfxVolume: Float = 0.8
    
    private init() {
        try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true, options: [])
    }
    
    func preload(_ names: [String]) {
        for name in names { _ = player(for: name) }
    }
    
    private func player(for name: String) -> AVAudioPlayer? {
        if let cached = players[name] { return cached }
        guard let url = Bundle.main.url(forResource: name, withExtension: nil) else { return nil }
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
        p.volume = max(0, min(1, volume)) * sfxVolume
        p.play()
    }
    
    func loadBGM(named name: String) {
        guard let url = Bundle.main.url(forResource: name, withExtension: nil) else {
            bgmPlayer = nil
            return
        }
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.numberOfLoops = -1
            p.volume = bgmVolume
            p.prepareToPlay()
            bgmPlayer = p
        } catch {
            bgmPlayer = nil
        }
    }
    
    func playBGM(loop: Bool = true) {
        guard let p = bgmPlayer else { return }
        p.numberOfLoops = loop ? -1 : 0
        if !p.isPlaying { p.play() }
    }
    func pauseBGM() { bgmPlayer?.pause() }
    func stopBGM() { bgmPlayer?.stop(); bgmPlayer?.currentTime = 0 }
    func setBGMVolume(_ volume: Float) { bgmVolume = max(0, min(1, volume)) }
    func setSFXVolume(_ volume: Float) { sfxVolume = max(0, min(1, volume)) }
}

private enum SFX {
    static let tap = "tap.mp3"
    static let attackNormal = "attack_normal.mp3"
    static let attackSpecial = "attack_special.mp3"
    static let win = "win.mp3"
    static let lose = "lose.mp3"
    static let enemyAttack = "attack_normal.mp3"
    static let battleBGM = "battle_bgm.mp3"
}

struct ContentView: View {
    @AppStorage("bgmEnabled") private var bgmEnabled: Bool = true
    @AppStorage("bgmVolume") private var bgmVolumeStore: Double = 0.6
    @AppStorage("sfxVolume") private var sfxVolumeStore: Double = 0.8
    
    @State private var showSettings: Bool = false
    
    @State private var showMainMenu: Bool = true
    @State private var showAbout: Bool = false
    
    @AppStorage("tokens") private var tokens: Double = 0.0
    @AppStorage("talent1Level") private var talent1Level: Int = 0
    @AppStorage("talent2Level") private var talent2Level: Int = 0
    @AppStorage("talent3Level") private var talent3Level: Int = 0
    @AppStorage("talent4Level") private var talent4Level: Int = 0
    @AppStorage("talent5Level") private var talent5Level: Int = 0
    @AppStorage("talent6Level") private var talent6Level: Int = 0
    
    @State private var playerHP: Int = 100
    @State private var playerMaxHP: Int = 100
    @State private var playerAttack: Int = 20
    @State private var playerDefense: Int = 10
    
    @State private var playerShieldMax: Int = 0
    @State private var playerShield: Int = 0
    
    @State private var cpuMaxHP: Int = 50
    @State private var cpuHP: Int = 50
    @State private var cpuAttack: Int = 5
    @State private var cpuDefense: Int = 0
    
    @State private var isBossRound: Bool = false
    @State private var lastWinWasBoss: Bool = false
    @State private var bossWinsCount: Int = 0
    
    @State private var defeatCount: Int = 0
    
    @State private var playerChoice: RPS? = nil
    @State private var cpuChoice: RPS? = nil
    @State private var message: String = "選擇你的出拳！"
    @State private var isGameOver: Bool = false
    @State private var shakePlayer: Bool = false
    @State private var shakeCPU: Bool = false
    
    @State private var selectedCharacter: Character? = nil
    @State private var winCountForChar2: Int = 0
    
    @State private var showUpgrade: Bool = false
    @State private var showSettlement: Bool = false
    @State private var tokensEarnedThisRun: Double = 0.0
    @State private var showTalentsSheet: Bool = false
    
    private let baseCritMultiplier: Double = 1.5
    private let baseBurstMultiplier: Double = 2.5
    private let luckyCritChance: Double = 0.5
    
    @State private var passiveMultiplier: Double = 1.0
    
    // New: run-scoped token standard, starts at 1.0 and doubles per boss win
    @State private var tokenStandard: Double = 1.0
    
    private var ignoreDefensePercent: Double {
        let lv = min(5, max(0, talent5Level))
        return Double(lv) * 0.05
    }
    private var currentEnemyDefense: Int {
        let base = isBossRound ? cpuDefense * 2 : cpuDefense
        let reduced = Double(base) * max(0.0, 1.0 - ignoreDefensePercent)
        return Int(reduced.rounded(.toNearestOrAwayFromZero))
    }
    
    private var computedShieldMax: Int {
        let lv = min(100, max(0, talent6Level))
        return lv * 5
    }
    private var currentPassiveMultiplier: Double {
        var mult = 1.0 + 0.1 * Double(min(5, talent4Level))
        if talent4Level >= 5 { mult += 0.25 }
        return mult
    }
    private func currentTotalMultiplier(for character: Character) -> Double {
        let base: Double
        switch character {
        case .強運戰士: base = baseCritMultiplier
        case .蓄力鬥士: base = baseBurstMultiplier
        case .治療祭司: base = 0.5
        }
        return base * currentPassiveMultiplier
    }
    
    var body: some View {
        ZStack {
            lightMedievalBackground
            VStack {
                Spacer(minLength: 0)
                if showMainMenu {
                    mainMenuView
                } else if selectedCharacter == nil {
                    characterSelectionView
                } else {
                    gameView
                }
                Spacer(minLength: 0)
            }
            if showUpgrade { overlayCard(upgradeOverlay) }
            if showSettlement { overlayCard(settlementOverlay) }
        }
        .onAppear {
            AudioManager.shared.preload([
                SFX.tap, SFX.attackNormal, SFX.attackSpecial,
                SFX.win, SFX.lose, SFX.enemyAttack
            ])
            AudioManager.shared.setBGMVolume(Float(bgmVolumeStore))
            AudioManager.shared.setSFXVolume(Float(sfxVolumeStore))
            AudioManager.shared.loadBGM(named: SFX.battleBGM)
            // Play BGM on main UI as well if enabled
            if bgmEnabled {
                AudioManager.shared.playBGM(loop: true)
            }
        }
        .onChange(of: bgmVolumeStore) { _, v in AudioManager.shared.setBGMVolume(Float(v)) }
        .onChange(of: sfxVolumeStore) { _, v in AudioManager.shared.setSFXVolume(Float(v)) }
        .sheet(isPresented: $showTalentsSheet) {
            themedContainer {
                TalentSheet(tokens: $tokens,
                            talent1Level: $talent1Level,
                            talent2Level: $talent2Level,
                            talent3Level: $talent3Level,
                            talent4Level: $talent4Level,
                            talent5Level: $talent5Level,
                            talent6Level: $talent6Level)
            }
        }
        .sheet(isPresented: $showAbout) {
            themedContainer { AboutView { showAbout = false } }
        }
        .sheet(isPresented: $showSettings) {
            themedContainer {
                SettingsView(bgmEnabled: $bgmEnabled,
                             bgmVolume: $bgmVolumeStore,
                             sfxVolume: $sfxVolumeStore,
                             onClose: { showSettings = false })
                .onChange(of: bgmEnabled) { _, on in
                    if on {
                        AudioManager.shared.loadBGM(named: SFX.battleBGM)
                        AudioManager.shared.playBGM(loop: true)
                    } else {
                        AudioManager.shared.stopBGM()
                    }
                }
            }
        }
    }
    
    // MARK: - Themed Background
    private var lightMedievalBackground: some View {
        ZStack {
            LinearGradient(colors: [
                Color(red: 0.98, green: 0.96, blue: 0.90),
                Color(red: 0.94, green: 0.90, blue: 0.82)
            ], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
            RadialGradient(colors: [Color.white.opacity(0.25), .clear],
                           center: .center, startRadius: 20, endRadius: 600)
                .blur(radius: 40)
        }
    }
    private func parchmentCard(_ content: () -> some View) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(red: 1.00, green: 0.98, blue: 0.93).opacity(0.92))
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color(red: 0.75, green: 0.58, blue: 0.25).opacity(0.7), lineWidth: 2)
        }
        .overlay(content())
        .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 6)
    }
    private func themedContainer<Content: View>(@ViewBuilder content: @escaping () -> Content) -> some View {
        ZStack {
            lightMedievalBackground
            VStack {
                content()
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.white.opacity(0.9))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(Color(red: 0.75, green: 0.58, blue: 0.25).opacity(0.7), lineWidth: 1.5)
                            )
                    )
                    .padding()
            }
        }
    }
    private func overlayCard<Content: View>(_ inner: Content) -> some View {
        ZStack {
            Color.black.opacity(0.15).ignoresSafeArea()
            inner
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.white.opacity(0.92))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(Color(red: 0.75, green: 0.58, blue: 0.25).opacity(0.7), lineWidth: 1.5)
                        )
                )
                .shadow(color: .black.opacity(0.1), radius: 12, x: 0, y: 6)
                .padding(24)
        }
        .transition(.opacity.combined(with: .scale))
    }
    
    // MARK: - Main Menu
    private var mainMenuView: some View {
        VStack(spacing: 22) {
            VStack(spacing: 6) {
                Label("我獨自猜拳", systemImage: "shield.lefthalf.filled")
                    .font(.system(size: 34, weight: .heavy, design: .serif))
                    .frame(maxWidth: .infinity, alignment: .center)
                Text("Rock · Paper · Scissors · Rogue")
                    .font(.footnote.smallCaps())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(.top, 6)
            
            VStack(spacing: 14) {
                // Icon changed to a more widely supported symbol
                menuCardButton(title: "開始冒險", systemImage: "shield", accent: .orange) {
                    AudioManager.shared.play(SFX.tap, volume: 0.8)
                    resetToCharacterSelect()
                    showMainMenu = false
                    if bgmEnabled {
                        AudioManager.shared.loadBGM(named: SFX.battleBGM)
                        AudioManager.shared.playBGM(loop: true)
                    }
                }
                menuCardButton(title: "天賦", systemImage: "star.circle", accent: .yellow) {
                    AudioManager.shared.play(SFX.tap, volume: 0.8)
                    showTalentsSheet = true
                }
                menuCardButton(title: "設定", systemImage: "gearshape.2", accent: .blue) {
                    AudioManager.shared.play(SFX.tap, volume: 0.8)
                    showSettings = true
                }
                menuCardButton(title: "關於", systemImage: "book", accent: .teal) {
                    AudioManager.shared.play(SFX.tap, volume: 0.8)
                    showAbout = true
                }
            }
            .padding(.horizontal, 24)
            
            VStack(spacing: 4) {
                Text("代幣：\(String(format: "%.2f", tokens))")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("在設定裡可調整 BGM / SFX 音量")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 4)
        }
        .padding(.vertical, 24)
        .frame(maxWidth: 520)
        .background(parchmentCard { EmptyView() })
        .padding(.horizontal, 20)
    }
    private func menuCardButton(title: String, systemImage: String, accent: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 24, weight: .black))
                    .frame(width: 28, alignment: .leading)
                Text(title)
                    .font(.system(.title3, design: .serif).weight(.bold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.primary)
            .padding()
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.9))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(accent.opacity(0.6), lineWidth: 1.5)
                    )
            )
            .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 4)
        }
        .buttonStyle(ScaleButtonStyle())
    }
    
    // MARK: - Character Selection
    private var characterSelectionView: some View {
        VStack(spacing: 24) {
            Text("選擇職業")
                .font(.system(.largeTitle, design: .serif).bold())
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 8)
            
            VStack(spacing: 16) {
                ForEach(Character.allCases) { character in
                    Button {
                        AudioManager.shared.play(SFX.tap, volume: 0.8)
                        choose(character)
                        if bgmEnabled { AudioManager.shared.playBGM(loop: true) }
                    } label: {
                        HStack(spacing: 16) {
                            Image(systemName: character.icon)
                                .font(.system(size: 28, weight: .bold))
                                .frame(width: 36)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(character.name).font(.headline)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(character.description)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text(String(format: "當前被動倍率 ×%.2f", currentPassiveMultiplier))
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    Text(String(format: "目前總倍率 ×%.2f", currentTotalMultiplier(for: character)))
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
                                .fill(Color.white.opacity(0.9))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(Color(red: 0.75, green: 0.58, blue: 0.25).opacity(0.7), lineWidth: 1.5)
                                )
                        )
                        .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 3)
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
            }
            .padding(.horizontal, 20)
            
            VStack(spacing: 8) {
                Text("代幣：\(String(format: "%.2f", tokens))").font(.headline)
                HStack(spacing: 12) {
                    Button {
                        AudioManager.shared.play(SFX.tap, volume: 0.8)
                        showTalentsSheet = true
                    } label: {
                        Label("前往天賦", systemImage: "star.circle")
                            .font(.headline)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Color.orange.opacity(0.2), in: Capsule())
                    }
                    .buttonStyle(ScaleButtonStyle())
                    
                    Button {
                        AudioManager.shared.play(SFX.tap, volume: 0.8)
                        // Do not show settlement; just go back to main menu
                        showMainMenu = true
                        selectedCharacter = nil
                        resetGame()
                        // 保留 BGM 在主畫面播放
                    } label: {
                        Label("返回大廳", systemImage: "house")
                            .font(.headline)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Color.gray.opacity(0.2), in: Capsule())
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
            }
            .padding(.top, 4)
            
            Text("提示：可於遊戲中按「重置(回選角)」回到選角畫面")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal)
        }
        .padding(.vertical)
        .frame(maxWidth: 700)
        .background(parchmentCard { EmptyView() })
        .padding(.horizontal, 16)
    }
    
    // MARK: - Game View
    private var gameView: some View {
        VStack(spacing: 20) {
            Text("我獨自猜拳")
                .font(.system(.largeTitle, design: .serif).bold())
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 8)
            
            if let selectedCharacter {
                HStack(spacing: 8) {
                    Image(systemName: selectedCharacter.icon)
                    Text("職業：\(selectedCharacter.name)")
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
            
            // 屬性與進度
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
            
            // HP + Shield Bars 疊層
            VStack(spacing: 12) {
                hpRow(title: "玩家",
                      hp: playerHP,
                      maxHP: playerMaxHP,
                      shield: playerShield,
                      maxShield: playerShieldMax)
                    .modifier(Shake(animatableData: shakePlayer ? 1 : 0))
                hpRow(title: isBossRound ? "Boss" : "電腦",
                      hp: cpuHP,
                      maxHP: currentEnemyMaxHP,
                      shield: 0,
                      maxShield: 0) // 敵方不顯示護盾
                    .modifier(Shake(animatableData: shakeCPU ? 1 : 0))
            }
            .padding(.horizontal)
            
            // Choices
            HStack(spacing: 24) {
                choiceCard(owner: "玩家", choice: playerChoice)
                Image(systemName: "bolt.horizontal.fill")
                    .foregroundStyle(.secondary)
                choiceCard(owner: isBossRound ? "Boss" : "電腦", choice: cpuChoice)
            }
            .padding(.horizontal)
            
            // 訊息 + 治療提示
            VStack(spacing: 6) {
                Text(message)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .center)
                    .padding(.horizontal)
                if selectedCharacter == .治療祭司 {
                    Text("提示：治療不會影響護盾值")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.horizontal)
                }
            }
            
            // 操作按鈕
            HStack(spacing: 12) {
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
                        .background(Color.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color(red: 0.75, green: 0.58, blue: 0.25).opacity(0.7), lineWidth: 1.5)
                        )
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .disabled(isGameOver || showUpgrade || showSettlement)
                }
            }
            .padding(.horizontal)
            
            // 重置/返回
            HStack(spacing: 12) {
                Button {
                    AudioManager.shared.play(SFX.tap, volume: 0.8)
                    forceShowSettlementAsDefeat()
                } label: {
                    Text(isGameOver ? "再選角色" : "重置(回選角)")
                        .font(.headline)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.yellow.opacity(0.25), in: Capsule())
                }
                .buttonStyle(ScaleButtonStyle())
                
                Button {
                    AudioManager.shared.play(SFX.tap, volume: 0.8)
                    forceShowSettlementAsDefeat()
                    showMainMenu = true
                    selectedCharacter = nil
                    // 保留 BGM 在主畫面播放
                } label: {
                    Text("返回大廳")
                        .font(.headline)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.gray.opacity(0.2), in: Capsule())
                }
                .buttonStyle(ScaleButtonStyle())
            }
            .padding(.bottom, 12)
            .padding(.horizontal)
        }
        .padding(.vertical, 16)
        .frame(maxWidth: 900)
        .background(parchmentCard { EmptyView() })
        .padding(.horizontal, 16)
    }
    
    // MARK: - Derived enemy stats
    private var currentEnemyMaxHP: Int { isBossRound ? cpuMaxHP * 2 : cpuMaxHP }
    private var currentEnemyAttack: Int { isBossRound ? cpuAttack * 2 : cpuAttack }
    
    // MARK: - Upgrade Overlay
    private var upgradeOverlay: some View {
        VStack(spacing: 16) {
            Text(lastWinWasBoss ? "Boss 勝利！選擇雙倍強化" : "勝利！選擇一個強化")
                .font(.title2.bold())
            VStack(spacing: 12) {
                Button {
                    AudioManager.shared.play(SFX.tap, volume: 0.8)
                    applyUpgrade(.attack)
                } label: {
                    upgradeCard(
                        title: lastWinWasBoss ? "攻擊力 +10" : "攻擊力 +5",
                        icon: "flame",
                        subtitle: lastWinWasBoss ? "Boss 獎勵：雙倍強化" : "提升造成的傷害"
                    )
                }
                .buttonStyle(ScaleButtonStyle())
                
                Button {
                    AudioManager.shared.play(SFX.tap, volume: 0.8)
                    applyUpgrade(.defense)
                } label: {
                    upgradeCard(
                        title: lastWinWasBoss ? "防禦力 +6" : "防禦力 +3",
                        icon: "shield",
                        subtitle: lastWinWasBoss ? "Boss 獎勵：雙倍強化" : "減少受到的傷害"
                    )
                }
                .buttonStyle(ScaleButtonStyle())
                
                // 血量卡片改為兩行：第一行上限變化，第二行回復與括號說明
                Button {
                    AudioManager.shared.play(SFX.tap, volume: 0.8)
                    applyUpgrade(.maxHP)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 14) {
                            Image(systemName: "heart")
                                .font(.system(size: 24, weight: .bold))
                                .frame(width: 28, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(lastWinWasBoss ? "血量上限 +40" : "血量上限 +20")
                                    .font(.headline)
                                Text(lastWinWasBoss ? "回復 60 生命（不影響護盾）" : "回復 30 生命（不影響護盾）")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.white.opacity(0.95), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color(red: 0.75, green: 0.58, blue: 0.25).opacity(0.7), lineWidth: 1.2)
                        )
                    }
                }
                .buttonStyle(ScaleButtonStyle())
            }
            .padding(.horizontal)
        }
    }
    
    // MARK: - Settlement Overlay
    private var settlementOverlay: some View {
        VStack(spacing: 16) {
            Text("結算")
                .font(.largeTitle.bold())
            VStack(alignment: .leading, spacing: 6) {
                Label("一般擊敗：\(defeatCount)", systemImage: "trophy")
                Label("Boss 擊敗：\(bossWinsCount)", systemImage: "crown")
                Label("獲得代幣：\(String(format: "%.2f", tokensEarnedThisRun))", systemImage: "bitcoinsign.circle")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
                    // 保留 BGM 在主畫面播放
                } label: {
                    Text("領取並返回大廳")
                        .font(.headline)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.orange.opacity(0.2), in: Capsule())
                }
                .buttonStyle(ScaleButtonStyle())
                
                Button {
                    AudioManager.shared.play(SFX.tap, volume: 0.8)
                    tokens += tokensEarnedThisRun
                    tokensEarnedThisRun = 0
                    showSettlement = false
                    resetToCharacterSelect()
                    showTalentsSheet = true
                    // 保留 BGM 在主畫面播放
                } label: {
                    Text("領取並前往天賦")
                        .font(.headline)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.yellow.opacity(0.3), in: Capsule())
                }
                .buttonStyle(ScaleButtonStyle())
            }
        }
    }
    
    private func upgradeCard(title: String, icon: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .bold))
                .frame(width: 28, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.95), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(red: 0.75, green: 0.58, blue: 0.25).opacity(0.7), lineWidth: 1.2)
        )
    }
    
    // MARK: - UI Parts
    private func hpRow(title: String, hp: Int, maxHP: Int, shield: Int, maxShield: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Text("\(max(0, hp))/\(maxHP)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            ZStack(alignment: .leading) {
                // 底層：紅色 HP 條
                Capsule()
                    .fill(Color.red.opacity(0.25))
                    .frame(height: 10)
                GeometryReader { geo in
                    let width = geo.size.width
                    let hpRatio = max(0, min(1, Double(hp) / Double(maxHP)))
                    let shieldRatio = maxShield > 0 ? max(0, min(1, Double(shield) / Double(maxShield))) : 0
                    // 紅色實際 HP 長度
                    let hpWidth = width * hpRatio
                    // 黃色護盾長度（覆蓋層）
                    let shieldWidth = width * shieldRatio
                    
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.red)
                            .frame(width: hpWidth, height: 10)
                        Capsule()
                            .fill(Color.yellow)
                            .frame(width: shieldWidth, height: 10)
                            .shadow(color: .yellow.opacity(0.25), radius: 2, x: 0, y: 0)
                    }
                }
                .frame(height: 10)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                )
            }
        }
        .padding(.horizontal)
    }
    
    private func choiceCard(owner: String, choice: RPS?) -> some View {
        VStack(spacing: 8) {
            Text(owner)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.95))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color(red: 0.75, green: 0.58, blue: 0.25).opacity(0.7), lineWidth: 1.2)
                    )
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
            if !extraMsg.isEmpty { baseMsg += " " + extraMsg.joined(separator: "，") }
            message = baseMsg
            hitCPU()
            
            if cpuHP <= 0 {
                refillShield()
                AudioManager.shared.play(SFX.win, volume: 1.0)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    handleEnemyDefeated()
                }
            }
            
        case .lose:
            let incomingRaw = max(1, currentEnemyAttack - playerDefense)
            let afterShield = applyDamageToShieldThenHP(incomingRaw)
            message = "你輸了！你受到 \(afterShield) 傷害。"
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
            AudioManager.shared.play(SFX.lose, volume: 1.0)
        }
    }
    
    private func handleEnemyDefeated() {
        if isBossRound {
            bossWinsCount += 1
            // Double the token standard on each boss win
            tokenStandard *= 2.0
            
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
        // Reward uses the current run's tokenStandard and counts all defeats equally
        tokenStandard * Double(defeatCount + bossWinsCount)
    }
    
    private enum Upgrade { case attack, defense, maxHP }
    
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
            message = "升級成功！血量上限 +\(hpGain)\n回復 \(healed) 生命（不影響護盾）"
        }
        
        showUpgrade = false
        lastWinWasBoss = false
        
        cpuHP = currentEnemyMaxHP
        cpuChoice = nil
        playerChoice = nil
        message += "，新的一場開始！"
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
        // Reset token standard on returning to character select
        tokenStandard = 1.0
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
        if talent4Level >= 5 { passiveMultiplier += 0.25 }
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
        
        // New run: reset token standard to 1.0
        tokenStandard = 1.0
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
    
    // New: halve damage absorbed by shield; HP damage unchanged
    private func applyDamageToShieldThenHP(_ damage: Int) -> Int {
        var remaining = damage
        var totalHPDamage = 0
        
        if playerShield > 0 && remaining > 0 {
            // Effective damage to shield is halved
            // Compute how much effective damage we can absorb given current shield
            // Each 1 shield absorbs 2 incoming damage (since incoming/2 is applied)
            let maxAbsorbableIncoming = playerShield * 2
            let incomingToShield = min(maxAbsorbableIncoming, remaining)
            // Effective deduction on shield is floor(incomingToShield / 2)
            let shieldDeduction = incomingToShield / 2
            playerShield -= shieldDeduction
            remaining -= incomingToShield
        }
        
        if remaining > 0 {
            let before = playerHP
            playerHP = max(0, playerHP - remaining)
            totalHPDamage = before - playerHP
        }
        return totalHPDamage
    }
    
    private func refillShield() { playerShield = playerShieldMax }
    
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
    
    private func forceShowSettlementAsDefeat() {
        guard !showSettlement else { return }
        tokensEarnedThisRun = calcTokenReward()
        isGameOver = true
        showUpgrade = false
        showSettlement = true
        message = "你選擇結束本局，以下是結算。"
    }
}

// MARK: - Button scale style
struct ScaleButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.96
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Settings View
struct SettingsView: View {
    @Binding var bgmEnabled: Bool
    @Binding var bgmVolume: Double
    @Binding var sfxVolume: Double
    var onClose: (() -> Void)?
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("音樂")) {
                    Toggle("啟用背景音樂", isOn: $bgmEnabled)
                    HStack {
                        Image(systemName: "speaker.slash")
                        Slider(value: $bgmVolume, in: 0...1, step: 0.01)
                        Image(systemName: "speaker.wave.3")
                    }
                    .disabled(!bgmEnabled)
                    .opacity(bgmEnabled ? 1 : 0.4)
                }
                Section(header: Text("音效")) {
                    HStack {
                        Image(systemName: "speaker.slash")
                        Slider(value: $sfxVolume, in: 0...1, step: 0.01)
                        Image(systemName: "speaker.wave.3")
                    }
                }
                Section {
                    Text("提示：背景音樂使用 .ambient 音訊類別，可與其他 App 混音。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("設定")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { onClose?() }
                }
            }
        }
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
    // Updated: starts at 20, +5 per current level
    private func shieldCostFor(level: Int) -> Double { Double(20 + level * 5) }
    private func canUpgradeShield(level: Int) -> Bool {
        guard level < 100 else { return false }
        let cost = shieldCostFor(level: level)
        return tokens + 1e-9 >= cost
    }
    
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("代幣：\(String(format: "%.2f", tokens))")) { EmptyView() }
                
                talentRow(
                    title: "攻擊力",
                    desc: "每級 +5，達 5 級時額外 +25（上限 5 級）。",
                    level: $talent1Level,
                    computePreview: { lv in
                        let base = lv * 5 + (lv >= 5 ? 25 : 0)
                        return "+\(base) ATK"
                    },
                    maxLevel: 5,
                    costProvider: costFor(level:),
                    canUpgrade: canUpgrade(level:),
                    onUpgrade: { lv, cost in tokens -= cost; return min(5, lv + 1) }
                )
                talentRow(
                    title: "防禦力",
                    desc: "每級 +5，達 5 級時額外 +25（上限 5 級）。",
                    level: $talent2Level,
                    computePreview: { lv in
                        let base = lv * 5 + (lv >= 5 ? 25 : 0)
                        return "+\(base) DEF"
                    },
                    maxLevel: 5,
                    costProvider: costFor(level:),
                    canUpgrade: canUpgrade(level:),
                    onUpgrade: { lv, cost in tokens -= cost; return min(5, lv + 1) }
                )
                talentRow(
                    title: "生命上限",
                    desc: "每級 +10，達 5 級時額外 +50（上限 5 級）。",
                    level: $talent3Level,
                    computePreview: { lv in
                        let base = lv * 10 + (lv >= 5 ? 50 : 0)
                        return "+\(base) MAX HP"
                    },
                    maxLevel: 5,
                    costProvider: costFor(level:),
                    canUpgrade: canUpgrade(level:),
                    onUpgrade: { lv, cost in tokens -= cost; return min(5, lv + 1) }
                )
                talentRow(
                    title: "角色被動倍率",
                    desc: "每級 +10%，達 5 級時額外 +0.25（上限 5 級）。",
                    level: $talent4Level,
                    computePreview: { lv in
                        var mult = 1.0 + 0.1 * Double(min(5, lv))
                        if lv >= 5 { mult += 0.25 }
                        return String(format: "×%.2f 被動倍率", mult)
                    },
                    maxLevel: 5,
                    costProvider: costFor(level:),
                    canUpgrade: canUpgrade(level:),
                    onUpgrade: { lv, cost in tokens -= cost; return min(5, lv + 1) }
                )
                
                // 無視防禦：百分比 + 成本 10 倍
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("無視防禦").font(.headline)
                        Text("每級 +5% 無視敵方防禦，達 5 級共 25%（上限 5 級）。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        let percent = talent5Level * 5
                        Text("無視防禦 \(percent)%")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(spacing: 6) {
                        Text("Lv. \(talent5Level)/5")
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                        Button {
                            let lv = talent5Level
                            guard lv < 5 else { return }
                            let baseCost = costFor(level: lv)
                            let cost = baseCost * 10
                            guard tokens + 1e-9 >= cost else { return }
                            tokens -= cost
                            talent5Level = min(5, lv + 1)
                        } label: {
                            if talent5Level >= 5 {
                                Text("已滿級")
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color.gray.opacity(0.2), in: Capsule())
                            } else {
                                let baseCost = costFor(level: talent5Level)
                                let cost = baseCost * 10
                                Text("升級(\(String(format: "%.1f", cost)))")
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background((tokens + 1e-9 >= cost) ? Color.orange.opacity(0.2) : Color.gray.opacity(0.2), in: Capsule())
                            }
                        }
                        .disabled({
                            let lv = talent5Level
                            guard lv < 5 else { return true }
                            let baseCost = costFor(level: lv)
                            let cost = baseCost * 10
                            return !(tokens + 1e-9 >= cost)
                        }())
                    }
                }
                .padding(.vertical, 6)
                
                // 護盾：單句 + 成本從 20 起遞增（每級 +5）
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("護盾").font(.headline)
                        Text("每級 +5 護盾，最多 100 級，勝利時自動回滿護盾。")
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
                                    .background(canUpgradeShield(level: talent6Level) ? Color.orange.opacity(0.2) : Color.gray.opacity(0.2), in: Capsule())
                            }
                        }
                        .disabled(!canUpgradeShield(level: talent6Level))
                    }
                }
                .padding(.vertical, 6)
                
                Section {
                    Text("提示：護盾無法被治療或能力值回復。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("天賦")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("關閉") { dismiss() }
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
                            .background((canUpgrade(level.wrappedValue)) ? Color.orange.opacity(0.2) : Color.gray.opacity(0.2), in: Capsule())
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
