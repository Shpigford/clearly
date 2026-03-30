import SwiftUI

struct ScratchpadContentView: View {
    @Binding var text: String
    @AppStorage("editorFontSize") private var fontSize: Double = 16

    var body: some View {
        ScratchpadEditorView(text: $text, fontSize: CGFloat(fontSize))
    }
}
