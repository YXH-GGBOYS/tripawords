import SwiftUI

/// The definition area for one word: one-line Chinese first, then word-atlas detail when the
/// word has it. (The 简/中 switch was dropped: without the deep level both were Chinese.)
struct WordResultView: View {
    let word: WordResult
    @State private var showImage = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if word.isProperNoun {
                Label("专有名词，不解释", systemImage: "person.text.rectangle")
                    .foregroundStyle(.secondary)
            } else if !word.found {
                Text("词库里没有这个词").foregroundStyle(.secondary)
            } else {
                briefSection
                if let atlas = word.atlas {
                    MidSection(atlas: atlas, showImage: $showImage)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(word.headword)
                .font(.system(size: 34, weight: .semibold, design: .serif))
                .textSelection(.enabled)
            HStack(spacing: 8) {
                if let ipa = word.ipa { Text(ipa).foregroundStyle(.secondary) }
                if word.query.lowercased() != word.headword.lowercased() {
                    Text("← \(word.query)").foregroundStyle(.tertiary)
                }
            }
            .font(.subheadline)
        }
    }

    private var briefSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(word.briefLines.enumerated()), id: \.offset) { _, line in
                Text(line).font(.title3)
            }
        }
    }
}

private struct MidSection: View {
    let atlas: AtlasEntry
    @Binding var showImage: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let ui = Thumbnail.image(atlas.image) {
                DisclosureGroup("插画", isExpanded: $showImage) {
                    Image(uiImage: ui)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 220)
                        .clipShape(.rect(cornerRadius: 10))
                }
                .font(.subheadline)
            }
            ForEach(Array(atlas.senses.enumerated()), id: \.offset) { _, sense in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(sense.pos) \(sense.zh)").font(.body.weight(.medium))
                    Text(sense.en).font(.callout).foregroundStyle(.secondary)
                }
            }
            if !atlas.examples.isEmpty {
                Section("例句") {
                    ForEach(Array(atlas.examples.enumerated()), id: \.offset) { _, ex in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ex.en).italic()
                            Text(ex.zh).font(.callout).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if !atlas.collocations.isEmpty {
                Section("搭配") {
                    ForEach(Array(atlas.collocations.enumerated()), id: \.offset) { _, c in
                        Text("\(c.en)  \(Text(c.zh).foregroundStyle(.secondary))")
                    }
                }
            }
            if !atlas.family.isEmpty {
                Section("词族") { Text(atlas.family.joined(separator: " · ")) }
            }
            if let tip = atlas.tip, !tip.isEmpty {
                Section("提示") { Text(tip) }
            }
        }
    }

    private struct Section<Content: View>: View {
        let title: String
        @ViewBuilder let content: Content
        init(_ title: String, @ViewBuilder content: () -> Content) {
            self.title = title
            self.content = content()
        }
        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                content
            }
        }
    }
}
