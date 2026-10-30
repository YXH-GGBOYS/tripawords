import SwiftData
import SwiftUI

/// The main screen: the definition fills the pane, controls sit in the thumb zone.
/// Lookup history has its own tab (HistoryView).
struct LookupView: View {
    @Bindable var model: AppModel
    @AppStorage("onboarded") private var onboarded = false
    @AppStorage("capturePaused") private var capturePaused = false
    @Query private var cards: [StudyCard]

    var body: some View {
        VStack(spacing: 0) {
            if capturePaused {
                // Paused in Settings and easy to forget: copies are read but not looked up.
                HStack(spacing: 12) {
                    Label("取词已暂停，复制的词不会显示", systemImage: "pause.circle").font(.callout)
                    Spacer(minLength: 0)
                    Button("恢复") { capturePaused = false }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
                .padding(12)
                .background(.orange.opacity(0.2), in: .rect(cornerRadius: 12))
                .padding([.horizontal, .top], 12)
            }
            if model.watcher.promptSuspected {
                PastePromptBanner { model.watcher.promptSuspected = false }
                    .padding([.horizontal, .top], 12)
            }
            ScrollView {
                resultArea
                    .padding(20)
            }
            .frame(maxHeight: .infinity)
            .dropDestination(for: String.self) { items, _ in
                guard let text = items.first else { return false }
                return model.handle(text)
            }
            Divider()
            bottomBar
        }
        .fullScreenCover(isPresented: .constant(!onboarded)) {
            OnboardingView { onboarded = true }
        }
    }

    @ViewBuilder private var resultArea: some View {
        if model.dictionaryMissing {
            Text("词库没有打包进 App，重新编译前先跑 pipeline 脚本。").foregroundStyle(.red)
        } else {
            switch model.current {
            case .none:
                ContentUnavailableView("在左边复制一个词", systemImage: "doc.on.clipboard",
                                       description: Text("也可以把词拖到这里，或点下面的粘贴按钮。"))
            case .word(let word):
                WordResultView(word: word)
            case .sentence(let text, let tokens):
                VStack(alignment: .leading, spacing: 20) {
                    SentenceView(tokens: tokens, picked: model.picked?.headword) { model.pick($0, in: text) }
                    Divider()
                    if let picked = model.picked {
                        WordResultView(word: picked)
                    } else if tokens.contains(where: { $0.kind != .plain }) {
                        Text("点橙色的词看释义，带下划线的词也能点。").foregroundStyle(.secondary)
                    } else {
                        Text("这句话里没有可查的词。").foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button {
                if let word = currentWord { Speaker.shared.say(word.headword) }
            } label: {
                Image(systemName: "speaker.wave.2.fill").font(.title2)
            }
            .disabled(currentWord == nil)
            .accessibilityLabel("发音")

            Button {
                if let word = currentWord { model.addCard(for: word) }
            } label: {
                Label(isCard ? "已加入卡片" : "加入卡片",
                      systemImage: isCard ? "checkmark.rectangle.stack.fill" : "plus.rectangle.on.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .lineLimit(1)
            .disabled(currentWord?.found != true || isCard)

            PasteButton(payloadType: String.self) { strings in
                guard let text = strings.first else { return }
                Task { @MainActor in model.handle(text) }
            }
            .labelStyle(.iconOnly)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var isCard: Bool {
        _ = cards.count  // re-evaluate after a card is added or deleted
        return currentWord.map { model.card(for: $0) != nil } ?? false
    }

    private var currentWord: WordResult? {
        if case .word(let word) = model.current { return word }
        return model.picked
    }
}

/// Every word looked up, newest first. Tap to reopen it on the lookup tab.
struct HistoryView: View {
    let model: AppModel
    @Environment(\.modelContext) private var context
    @Query(sort: \LookupRecord.lookedUpAt, order: .reverse) private var history: [LookupRecord]
    @State private var search = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(filtered) { record in
                    Button { model.reopen(record.headword) } label: {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(record.headword).font(.body.weight(.medium))
                                Text(model.briefLine(for: record.headword))
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Text(record.lookedUpAt, format: .dateTime.month().day().hour().minute().locale(Locale(identifier: "zh_CN")))
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    .foregroundStyle(.primary)
                }
                .onDelete { offsets in
                    for i in offsets { context.delete(filtered[i]) }
                    try? context.save()
                }
            }
            .searchable(text: $search, prompt: "查过的词")
            .navigationTitle("历史（\(history.count)）")
            .overlay {
                if history.isEmpty {
                    ContentUnavailableView("还没有查过词", systemImage: "clock")
                }
            }
        }
    }

    private var filtered: [LookupRecord] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty ? history : history.filter { $0.headword.contains(q) }
    }
}

/// A copied sentence in large type, words marked in place: hard words highlighted,
/// other content words underlined, both tappable.
private struct SentenceView: View {
    let tokens: [SentenceToken]
    let picked: String?
    let select: (WordResult) -> Void

    var body: some View {
        FlowLayout(spacing: 4, lineSpacing: 10) {
            ForEach(units, id: \.first!.id) { unit in
                HStack(spacing: 0) {
                    ForEach(unit) { token in
                        Text(token.leading)
                        wordView(token)
                        Text(token.trailing)
                    }
                }
            }
        }
        .font(.title2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Tokens joined without a space wrap together.
    private var units: [[SentenceToken]] {
        tokens.reduce(into: []) { units, token in
            if token.gluedToPrevious, !units.isEmpty { units[units.count - 1].append(token) } else { units.append([token]) }
        }
    }

    @ViewBuilder private func wordView(_ token: SentenceToken) -> some View {
        // Same padding on every word so baselines line up whether or not it is highlighted.
        if let word = token.word, token.kind != .plain {
            let isPicked = word.headword == picked
            Button { select(word) } label: {
                Text(token.surface)
                    .fontWeight(token.kind == .hard ? .semibold : .regular)
                    .underline(token.kind == .content && !isPicked, pattern: .dot, color: .gray)
                    .foregroundStyle(isPicked ? .white : .primary)
                    .padding(.horizontal, 4).padding(.vertical, 3)
                    .background(background(token.kind, isPicked), in: .rect(cornerRadius: 6))
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
        } else {
            Text(token.surface).padding(.horizontal, 4).padding(.vertical, 3)
        }
    }

    private func background(_ kind: SentenceToken.Kind, _ isPicked: Bool) -> Color {
        if isPicked { return .orange }
        return kind == .hard ? .orange.opacity(0.22) : .clear
    }
}

/// Lays subviews out left to right and wraps them like words in a paragraph.
private struct FlowLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let points = arrange(width: bounds.width, subviews: subviews).points
        for (subview, point) in zip(subviews, points) {
            subview.place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified)
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (points: [CGPoint], size: CGSize) {
        var points: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            points.append(CGPoint(x: x, y: y))
            maxX = max(maxX, x + size.width)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return (points, CGSize(width: maxX, height: y + rowHeight))
    }
}
