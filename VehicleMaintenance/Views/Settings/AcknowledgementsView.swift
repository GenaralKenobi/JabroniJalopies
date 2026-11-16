import SwiftUI

/// The open-source licenses for the libraries the app includes (their licenses require
/// passing these notices on to people who receive the app).
struct AcknowledgementsView: View {
    private let text: String = {
        guard let url = Bundle.main.url(forResource: "Acknowledgements", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "The license notices couldn't be loaded."
        }
        return text
    }()

    var body: some View {
        ScrollView {
            Text(text)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle("Open-Source Licenses")
        .navigationBarTitleDisplayMode(.inline)
    }
}
