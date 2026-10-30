import SwiftData
import SwiftUI
import UIKit

enum Thumbnail {
    static func image(_ file: String?) -> UIImage? {
        guard let file,
              let url = Bundle.main.url(forResource: file, withExtension: nil, subdirectory: "thumb")
        else { return nil }
        return UIImage(contentsOfFile: url.path)
    }
}

/// Card back: meaning first, etymology in small grey type under it, then the illustration.
struct CardBackView: View {
    let card: StudyCard

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(card.meaning).font(.title3)
            if !card.etymology.isEmpty {
                Text(card.etymology).font(.footnote).foregroundStyle(.secondary)
            }
            if !card.rootFamily.isEmpty {
                Text(card.rootFamily).font(.footnote).foregroundStyle(.secondary)
            }
            if let image = Thumbnail.image(card.imageName) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 200)
                    .clipShape(.rect(cornerRadius: 10))
            }
            if let context = card.context, !context.isEmpty {
                Text(context).font(.callout).italic().foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Card list, today's count and the way into review and settings.
struct CardsHomeView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \StudyCard.createdAt, order: .reverse) private var cards: [StudyCard]
    @AppStorage("newPerDay") private var newPerDay = ReviewScheduler.defaultNewPerDay
    @AppStorage("reviewsPerDay") private var reviewsPerDay = ReviewScheduler.defaultReviewsPerDay
    @State private var search = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        StudySessionView()
                    } label: {
                        LabeledContent("今日待复习", value: "\(todayCount)")
                            .font(.title3.weight(.semibold))
                    }
                    .disabled(todayCount == 0)
                }
                Section("全部卡片（\(cards.count)）") {
                    ForEach(filtered) { card in
                        NavigationLink {
                            CardEditorView(card: card)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(card.word).font(.body.weight(.medium))
                                Text(card.meaning).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                    .onDelete { offsets in
                        for i in offsets { context.delete(filtered[i]) }
                        try? context.save()
                    }
                }
            }
            .searchable(text: $search, prompt: "单词、释义或标签")
            .navigationTitle("卡片")
            .toolbar {
                NavigationLink { SettingsView() } label: { Image(systemName: "gearshape") }
            }
            .overlay {
                if cards.isEmpty {
                    ContentUnavailableView("还没有卡片", systemImage: "rectangle.stack",
                                           description: Text("查词时点底部的「加入卡片」。"))
                }
            }
        }
    }

    private var todayCount: Int {
        _ = cards.count  // re-evaluate when cards change
        return ReviewScheduler(context: context, newPerDay: newPerDay, reviewsPerDay: reviewsPerDay).todayCount()
    }

    private var filtered: [StudyCard] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return cards }
        return cards.filter {
            $0.word.lowercased().contains(q) || $0.meaning.contains(q) || $0.tags.contains { $0.lowercased().contains(q) }
        }
    }
}

struct CardEditorView: View {
    @Bindable var card: StudyCard
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var allCards: [StudyCard]
    @State private var tagText = ""

    var body: some View {
        Form {
            Section("释义") { TextField("释义", text: $card.meaning, axis: .vertical) }
            Section("来源") {
                TextField("哪本书或哪个游戏", text: $card.source)
                if !knownSources.isEmpty {
                    Menu("选以前用过的") {
                        ForEach(knownSources, id: \.self) { s in Button(s) { card.source = s } }
                    }
                }
            }
            Section("原句") { TextField("复制时的原句", text: contextBinding, axis: .vertical) }
            Section("标签（逗号分隔）") {
                TextField("如 ASOIAF, 军事", text: $tagText)
                    .onSubmit(applyTags)
            }
            Section("预览背面") { CardBackView(card: card) }
            Section {
                Button("删除卡片", role: .destructive) {
                    context.delete(card)
                    try? context.save()
                    dismiss()
                }
            }
        }
        .navigationTitle(card.word)
        .onAppear { tagText = card.tags.joined(separator: ", ") }
        .onDisappear {
            applyTags()
            if !card.source.isEmpty { UserDefaults.standard.set(card.source, forKey: "lastSource") }
            try? context.save()
        }
    }

    private var contextBinding: Binding<String> {
        Binding(get: { card.context ?? "" }, set: { card.context = $0.isEmpty ? nil : $0 })
    }

    private var knownSources: [String] {
        Array(Set(allCards.map(\.source).filter { !$0.isEmpty })).sorted()
    }

    private func applyTags() {
        card.tags = tagText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}

struct SettingsView: View {
    @AppStorage("newPerDay") private var newPerDay = ReviewScheduler.defaultNewPerDay
    @AppStorage("reviewsPerDay") private var reviewsPerDay = ReviewScheduler.defaultReviewsPerDay
    @AppStorage("capturePaused") private var capturePaused = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        Form {
            Section("取词") {
                Toggle("暂停取词", isOn: $capturePaused)
                Button("打开粘贴权限设置") { openURL(URL(string: UIApplication.openSettingsURLString)!) }
            }
            Section("每日上限") {
                Stepper("新卡 \(newPerDay) 张", value: $newPerDay, in: 0...100, step: 5)
                Stepper("复习 \(reviewsPerDay) 张", value: $reviewsPerDay, in: 10...500, step: 10)
            }
            Section("关于") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("插画与中档释义：Word Atlas contributors — CC BY 4.0。FoldPilot 改动了排版和数据格式。")
                    Link("CC BY 4.0 授权", destination: URL(string: "https://creativecommons.org/licenses/by/4.0/")!)
                    Link("Word Atlas", destination: URL(string: "https://github.com/designfuchen/word-atlas")!)
                    Text("简档词典：ECDICT（MIT）。复习算法：swift-fsrs（MIT）。")
                }
                .font(.footnote)
            }
        }
        .navigationTitle("设置")
    }
}
