import SwiftData
import SwiftUI

/// Today's study sitting: intro pages for new words, four quiz types for word-atlas words,
/// flip cards for everything else.
struct StudySessionView: View {
    @Environment(\.modelContext) private var context
    @AppStorage("newPerDay") private var newPerDay = ReviewScheduler.defaultNewPerDay
    @AppStorage("reviewsPerDay") private var reviewsPerDay = ReviewScheduler.defaultReviewsPerDay
    @State private var session: StudySession?

    var body: some View {
        Group {
            if let session, let step = session.current, let card = session.cards[step.word] {
                VStack(spacing: 0) {
                    ProgressView(value: Double(session.progress.done), total: Double(max(1, session.progress.total)))
                        .padding(.horizontal, 16)
                    StepView(step: step, card: card, atlas: session.atlasEntry(step.word),
                             scheduler: scheduler, session: session)
                        .id(step.id)
                }
            } else if session != nil {
                ContentUnavailableView("今天的学习完成了", systemImage: "checkmark.circle")
            } else {
                ProgressView()
            }
        }
        .navigationTitle("学习")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if session == nil {
                session = StudySession(scheduler: scheduler, store: try? DictionaryStore())
            }
        }
    }

    private var scheduler: ReviewScheduler {
        ReviewScheduler(context: context, newPerDay: newPerDay, reviewsPerDay: reviewsPerDay)
    }
}

private struct StepView: View {
    let step: StudyStep
    let card: StudyCard
    let atlas: AtlasEntry?
    let scheduler: ReviewScheduler
    let session: StudySession

    var body: some View {
        switch step.kind {
        case .intro:
            IntroView(card: card, atlas: atlas) { session.continueFromIntro() }
        case .flip:
            FlipView(card: card, intervals: scheduler.preview(card)) { session.answerFlip($0) }
        case .quiz(let kind):
            QuizView(step: step, kind: kind, card: card, atlas: atlas) { correct, elapsed, hinted in
                session.answerQuiz(correct: correct, elapsed: elapsed, hinted: hinted)
            }
        }
    }
}

private struct WordTitle: View {
    let word: String
    var body: some View {
        HStack {
            Text(word).font(.system(size: 36, weight: .semibold, design: .serif))
            Button { Speaker.shared.say(word) } label: { Image(systemName: "speaker.wave.2.fill") }
        }
        .frame(maxWidth: .infinity)
    }
}

/// "初见": everything about a new word, then continue.
private struct IntroView: View {
    let card: StudyCard
    let atlas: AtlasEntry?
    let next: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("新词").font(.caption).foregroundStyle(.secondary)
                    WordTitle(word: card.word)
                    CardBackView(card: card)
                    if let ex = atlas?.examples.first {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ex.en).italic()
                            Text(ex.zh).font(.callout).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(20)
            }
            Button("记住了，下一个", action: next)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(16)
        }
        .onAppear { Speaker.shared.say(card.word) }
    }
}

/// Self-rated flip card; each button shows when the card would come back.
private struct FlipView: View {
    let card: StudyCard
    let intervals: [ReviewAnswer: TimeInterval]
    let answer: (ReviewAnswer) -> Void
    @State private var flipped = false
    @State private var drag: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    WordTitle(word: card.word).padding(.top, 32)
                    if flipped {
                        CardBackView(card: card)
                    } else {
                        Text("点一下翻面").font(.footnote).foregroundStyle(.tertiary).frame(maxWidth: .infinity)
                    }
                }
                .padding(20)
            }
            .contentShape(.rect)
            .onTapGesture { flipped = true }
            .offset(x: drag)
            .gesture(DragGesture()
                .onChanged { drag = $0.translation.width }
                .onEnded { value in
                    drag = 0
                    if value.translation.width < -100 { answer(.forgot) } else if value.translation.width > 100 { answer(.knew) }
                })
            HStack(spacing: 8) {
                ForEach(ReviewAnswer.allCases, id: \.self) { a in
                    Button { answer(a) } label: {
                        VStack(spacing: 2) {
                            Text(a.label)
                            if let t = intervals[a] {
                                Text(ReviewScheduler.describe(t)).font(.caption2)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(a == .forgot ? .red : a == .fuzzy ? .orange : .green)
                }
            }
            .padding(16)
        }
    }
}

/// The four word-atlas question types. Shows right/wrong, then continues.
private struct QuizView: View {
    let step: StudyStep
    let kind: QuizKind
    let card: StudyCard
    let atlas: AtlasEntry?
    let done: (_ correct: Bool, _ elapsed: Duration, _ hinted: Bool) -> Void

    @State private var started = ContinuousClock.now
    @State private var picked: String?
    @State private var typed = ""
    @State private var hints = 0
    @State private var result: Bool?
    @State private var elapsed: Duration = .zero
    @FocusState private var typing: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(prompt).font(.caption).foregroundStyle(.secondary)
                    question
                    if kind == .spell { spellField } else { choiceList }
                    if let result { feedback(result) }
                }
                .padding(20)
            }
            if result != nil {
                Button("继续") { done(result ?? false, elapsed, hints > 0) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(16)
            }
        }
        .onAppear {
            started = .now
            if kind == .listen { Speaker.shared.say(card.word) }
            if kind == .spell { typing = true }
        }
    }

    private var prompt: String {
        switch kind {
        case .meaning: "选出这个词的意思"
        case .picture: "看图，选出空里的词"
        case .listen: "听发音，选出这个词"
        case .spell: "看图和释义，拼出这个词"
        }
    }

    @ViewBuilder private var question: some View {
        switch kind {
        case .meaning:
            WordTitle(word: card.word)
        case .listen:
            Button { Speaker.shared.say(card.word) } label: {
                Label("再听一遍", systemImage: "speaker.wave.3.fill").font(.title2)
            }
            .frame(maxWidth: .infinity)
        case .picture:
            image
            if let cloze = step.cloze { Text(cloze).font(.title3) }
        case .spell:
            image
            Text(card.meaning).font(.title3)
        }
    }

    @ViewBuilder private var image: some View {
        if let ui = Thumbnail.image(atlas?.image) {
            Image(uiImage: ui).resizable().scaledToFit().frame(maxWidth: 200)
                .clipShape(.rect(cornerRadius: 10)).frame(maxWidth: .infinity)
        }
    }

    private var choiceList: some View {
        VStack(spacing: 10) {
            ForEach(step.choices) { choice in
                Button { pick(choice.word) } label: {
                    Text(choice.label)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(background(for: choice.word), in: .rect(cornerRadius: 10))
                }
                .foregroundStyle(.primary)
                .allowsHitTesting(result == nil)  // not .disabled: keep the red/green answer colours readable
            }
        }
    }

    private func background(for word: String) -> Color {
        guard result != nil else { return Color.secondary.opacity(0.12) }
        if word == card.word { return .green.opacity(0.3) }
        if word == picked { return .red.opacity(0.3) }
        return Color.secondary.opacity(0.08)
    }

    private var spellField: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("输入单词", text: $typed)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.title2)
                .focused($typing)
                .onSubmit { check(typed) }
                .disabled(result != nil)
            HStack {
                Button("提示一个字母") {
                    hints += 1
                    typed = String(card.word.prefix(hints))
                }
                .disabled(result != nil || hints >= card.word.count - 1)
                Spacer()
                Button("确定") { check(typed) }.buttonStyle(.bordered).disabled(result != nil)
            }
        }
    }

    @ViewBuilder private func feedback(_ correct: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(correct ? "对了" : "正确答案是 \(card.word)", systemImage: correct ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(correct ? .green : .red)
                .font(.headline)
            Text(card.meaning).font(.callout).foregroundStyle(.secondary)
        }
    }

    private func pick(_ word: String) {
        picked = word
        finish(word == card.word)
    }

    private func check(_ text: String) {
        let answer = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard !answer.isEmpty else { return }
        finish(answer == card.word.lowercased())
    }

    private func finish(_ correct: Bool) {
        elapsed = ContinuousClock.now - started
        result = correct
        typing = false
        Speaker.shared.say(card.word)
    }
}
