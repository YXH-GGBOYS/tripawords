import SwiftUI
import UIKit

/// First-launch guide (plan §4.4): why FoldPilot reads the clipboard and how to stop the
/// per-copy paste prompt by setting "Paste from Other Apps" to Allow.
struct OnboardingView: View {
    let done: () -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("FoldPilot").font(.largeTitle.bold())
                Text("左半屏看书，右半屏开 FoldPilot。在书里选中一个词点「拷贝」，这边马上出释义。")
                    .font(.title3)

                VStack(alignment: .leading, spacing: 8) {
                    Text("为什么要读剪贴板").font(.headline)
                    Text("只有 FoldPilot 在屏幕上时才读，只用来查你刚复制的词。内容只存在这台手机上，不上传。")
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("一次性允许，以后不再弹窗").font(.headline)
                    Text("苹果默认每次都会问「允许粘贴吗」。点下面的按钮，在打开的页面里：")
                        .foregroundStyle(.secondary)
                    Text("「从其他 App 粘贴」→「允许」")
                        .font(.body.weight(.semibold))
                    Text("如果还看不到这一项，先回到书里复制一个词，再回来点按钮。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Button {
                    openURL(URL(string: UIApplication.openSettingsURLString)!)
                } label: {
                    Label("去开启", systemImage: "gearshape")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("已经开好了，开始用", action: done)
                    .frame(maxWidth: .infinity)
            }
            .padding(24)
        }
    }
}

/// Shown when a clipboard read looked like it waited on the paste prompt.
struct PastePromptBanner: View {
    let dismiss: () -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(spacing: 12) {
            Text("每次复制都弹窗？一次性允许就不弹了。")
                .font(.callout)
            Spacer(minLength: 0)
            Button("去设置") {
                openURL(URL(string: UIApplication.openSettingsURLString)!)
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            Button(action: dismiss) { Image(systemName: "xmark") }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.yellow.opacity(0.2), in: .rect(cornerRadius: 12))
    }
}
