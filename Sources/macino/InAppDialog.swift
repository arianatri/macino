import SwiftUI
import AppKit

extension Notification.Name { static let macinoCancelDialog = Notification.Name("macino.cancelInlineDialog") }

struct InAppDialog {
    let title: String
    let message: String
    var primaryTitle = "OK"
    var destructive = false
    var cancel: (() -> Void)? = nil
    let confirm: () -> Void
    var dismiss: () -> Void { cancel ?? confirm }
}

struct InAppDialogView: View {
    let dialog: InAppDialog
    var body: some View {
        ZStack {
            Color.black.opacity(0.18).contentShape(Rectangle()).onTapGesture { }
            VStack(alignment: .leading, spacing: 16) {
                Text(dialog.title).font(.headline).lineLimit(3)
                ScrollView { messageText }.frame(height: messageHeight)
                HStack {
                    Spacer()
                    if let cancel = dialog.cancel {
                        Button("Cancel", role: .cancel, action: cancel).keyboardShortcut(.cancelAction)
                    }
                    Button(dialog.primaryTitle, role: dialog.destructive ? .destructive : nil, action: dialog.confirm)
                        .keyboardShortcut(.defaultAction)
                }
            }.padding(20).frame(width: 350)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.primary.opacity(0.08)))
                .shadow(color: .black.opacity(0.16), radius: 18, y: 5)
                .onExitCommand(perform: dialog.dismiss)
                .accessibilityElement(children: .contain)
                .accessibilityLabel(dialog.title)
        }.clipShape(RoundedRectangle(cornerRadius: 22))
    }
    private var messageHeight: CGFloat {
        let bounds = (dialog.message as NSString).boundingRect(with: NSSize(width: 310, height: 10000), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: NSFont.systemFont(ofSize: 13)])
        return min(220, max(24, ceil(bounds.height) + 6))
    }
    private var messageText: some View {
        Text(dialog.message).font(.callout).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
    }
}
