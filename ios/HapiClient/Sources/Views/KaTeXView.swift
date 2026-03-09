import SwiftUI
import WebKit

struct KaTeXView: View {
    let latex: String
    let displayMode: Bool
    @Environment(\.colorScheme) private var colorScheme
    @State private var height: CGFloat = 24

    var body: some View {
        KaTeXWebView(
            latex: latex,
            displayMode: displayMode,
            textColor: colorScheme == .dark ? "#e0e0e0" : "#1a1a1a",
            height: $height
        )
        .frame(height: height)
        .frame(maxWidth: displayMode ? .infinity : nil, alignment: .leading)
    }
}

private struct KaTeXWebView: UIViewRepresentable {
    let latex: String
    let displayMode: Bool
    let textColor: String
    @Binding var height: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(height: $height)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "heightChanged")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false

        if let templateURL = Bundle.main.url(forResource: "katex-template", withExtension: "html", subdirectory: "KaTeX") {
            webView.loadFileURL(templateURL, allowingReadAccessTo: templateURL.deletingLastPathComponent())
        }

        context.coordinator.webView = webView
        context.coordinator.pendingLatex = latex
        context.coordinator.pendingDisplayMode = displayMode
        context.coordinator.pendingTextColor = textColor
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let escaped = latex
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
        let js = "renderLatex('\(escaped)', \(displayMode), '\(textColor)');"
        if context.coordinator.isLoaded {
            webView.evaluateJavaScript(js)
        } else {
            context.coordinator.pendingLatex = latex
            context.coordinator.pendingDisplayMode = displayMode
            context.coordinator.pendingTextColor = textColor
        }
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        @Binding var height: CGFloat
        var webView: WKWebView?
        var isLoaded = false
        var pendingLatex: String?
        var pendingDisplayMode: Bool = false
        var pendingTextColor: String = "#1a1a1a"

        init(height: Binding<CGFloat>) {
            _height = height
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoaded = true
            if let latex = pendingLatex {
                let escaped = latex
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "'", with: "\\'")
                    .replacingOccurrences(of: "\n", with: "\\n")
                let js = "renderLatex('\(escaped)', \(pendingDisplayMode), '\(pendingTextColor)');"
                webView.evaluateJavaScript(js)
                pendingLatex = nil
            }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "heightChanged", let h = message.body as? CGFloat, h > 0 {
                DispatchQueue.main.async {
                    self.height = h
                }
            }
        }
    }
}
