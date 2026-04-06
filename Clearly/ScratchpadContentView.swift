import SwiftUI

struct ScratchpadContentView: View {
    @Binding var text: String
    @AppStorage("editorFontSize") private var fontSize: Double = 16
    var onSave: (() -> Void)?

    var body: some View {
        ScratchpadEditorView(text: $text, fontSize: CGFloat(fontSize), onSave: onSave)
    }
}
