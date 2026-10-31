
// ===== HES STORE : extras iOS (ajoutés à AppDelegate.swift par le workflow) =====
import UIKit
import WebKit
import Capacitor

let hesChannelURL = "https://whatsapp.com/channel/0029Vb7Ibg5002T79MWH2r1p"

// MARK: - Utilitaires

func hesKeyWindow() -> UIWindow? {
    for scene in UIApplication.shared.connectedScenes {
        if let ws = scene as? UIWindowScene,
           let w = ws.windows.first(where: { $0.isKeyWindow }) {
            return w
        }
    }
    if let w = (UIApplication.shared.delegate?.window ?? nil) {
        return w
    }
    return UIApplication.shared.windows.first
}

func hesTopViewController() -> UIViewController? {
    var top = hesKeyWindow()?.rootViewController
    while let p = top?.presentedViewController {
        top = p
    }
    return top
}

func hesToast(_ text: String) {
    DispatchQueue.main.async {
        guard let win = hesKeyWindow() else { return }
        let l = UILabel()
        l.text = text
        l.textColor = .white
        l.font = UIFont.systemFont(ofSize: 14)
        l.textAlignment = .center
        l.backgroundColor = UIColor.black.withAlphaComponent(0.85)
        l.layer.cornerRadius = 18
        l.clipsToBounds = true
        l.sizeToFit()
        let w = l.frame.width + 32
        l.frame = CGRect(x: (win.bounds.width - w) / 2,
                         y: win.bounds.height - win.safeAreaInsets.bottom - 90,
                         width: w,
                         height: 36)
        win.addSubview(l)
        UIView.animate(withDuration: 0.3, delay: 2.0, options: [], animations: {
            l.alpha = 0
        }, completion: { _ in
            l.removeFromSuperview()
        })
    }
}

/* Fichier a telecharger (piece jointe ou type non affichable) -> telechargement natif */
func hesDecideResponse(_ response: WKNavigationResponse, _ handler: @escaping (WKNavigationResponsePolicy) -> Void) {
    if #available(iOS 14.5, *) {
        var attachment = false
        if let http = response.response as? HTTPURLResponse,
           let cd = http.value(forHTTPHeaderField: "Content-Disposition"),
           cd.lowercased().contains("attachment") {
            attachment = true
        }
        if attachment || !response.canShowMIMEType {
            handler(.download)
            return
        }
    }
    handler(.allow)
}

/* Telechargement : fichier recu -> feuille de partage (Enregistrer dans Fichiers, etc.) */
@available(iOS 14.5, *)
final class HesDownloader: NSObject, WKDownloadDelegate {
    private var keep: HesDownloader?
    private var fileURL: URL?

    override init() {
        super.init()
        keep = self
    }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        let url = dir.appendingPathComponent(suggestedFilename)
        fileURL = url
        completionHandler(url)
    }

    func downloadDidFinish(_ download: WKDownload) {
        let url = fileURL
        keep = nil
        guard let u = url else { return }
        DispatchQueue.main.async {
            guard let top = hesTopViewController() else { return }
            let vc = UIActivityViewController(activityItems: [u], applicationActivities: nil)
            if let pop = vc.popoverPresentationController {
                pop.sourceView = top.view
                pop.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 1, height: 1)
                pop.permittedArrowDirections = []
            }
            top.present(vc, animated: true, completion: nil)
        }
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        keep = nil
        hesToast("\u{00C9}chec du t\u{00E9}l\u{00E9}chargement")
    }
}

// MARK: - Fenetre (popup) du lecteur, dans l'appli

final class HesPopupDelegate: NSObject, WKNavigationDelegate, WKUIDelegate {
    weak var owner: HesWebProxy?

    func webViewDidClose(_ webView: WKWebView) {
        owner?.closePopup()
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil, let u = navigationAction.request.url {
            webView.load(URLRequest(url: u))
        }
        return nil
    }

    /* seuls http/https restent dans la fenetre, le reste s'ouvre dehors */
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = navigationAction.request.url, let scheme = url.scheme?.lowercased(),
           !["http", "https", "about", "blob", "data"].contains(scheme) {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        hesDecideResponse(navigationResponse, decisionHandler)
    }

    @available(iOS 14.5, *)
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = HesDownloader()
        hesToast("T\u{00E9}l\u{00E9}chargement d\u{00E9}marr\u{00E9}\u{2026}")
    }
}

/* Se place devant les delegues de Capacitor : ajoute popups + telechargements,
   et renvoie tout le reste a Capacitor (allowNavigation, errorPath, alertes, etc.) */
final class HesWebProxy: NSObject, WKNavigationDelegate, WKUIDelegate {
    weak var host: UIViewController?
    var origNav: WKNavigationDelegate?
    var origUI: WKUIDelegate?
    private var layer: UIView?
    private var popup: WKWebView?
    private let popupDelegate = HesPopupDelegate()

    init(host: UIViewController) {
        self.host = host
        super.init()
        popupDelegate.owner = self
    }

    override func responds(to aSelector: Selector!) -> Bool {
        if super.responds(to: aSelector) { return true }
        if let n = origNav as? NSObject, n.responds(to: aSelector) { return true }
        if let u = origUI as? NSObject, u.responds(to: aSelector) { return true }
        return false
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        if let n = origNav as? NSObject, n.responds(to: aSelector) { return n }
        if let u = origUI as? NSObject, u.responds(to: aSelector) { return u }
        return super.forwardingTarget(for: aSelector)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        return openPopup(configuration)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        hesDecideResponse(navigationResponse, decisionHandler)
    }

    @available(iOS 14.5, *)
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = HesDownloader()
        hesToast("T\u{00E9}l\u{00E9}chargement d\u{00E9}marr\u{00E9}\u{2026}")
    }

    func openPopup(_ configuration: WKWebViewConfiguration) -> WKWebView? {
        guard let win = hesKeyWindow() else { return nil }
        closePopup()

        let pw = WKWebView(frame: .zero, configuration: configuration)
        pw.navigationDelegate = popupDelegate
        pw.uiDelegate = popupDelegate
        pw.allowsBackForwardNavigationGestures = true
        pw.backgroundColor = .black
        pw.scrollView.backgroundColor = .black
        pw.translatesAutoresizingMaskIntoConstraints = false

        let lay = UIView()
        lay.backgroundColor = .black
        lay.translatesAutoresizingMaskIntoConstraints = false
        win.addSubview(lay)
        lay.addSubview(pw)

        let x = UIButton(type: .custom)
        x.setTitle("\u{2715}", for: .normal)
        x.setTitleColor(.white, for: .normal)
        x.titleLabel?.font = UIFont.systemFont(ofSize: 22)
        x.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        x.translatesAutoresizingMaskIntoConstraints = false
        x.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        lay.addSubview(x)

        NSLayoutConstraint.activate([
            lay.topAnchor.constraint(equalTo: win.topAnchor),
            lay.bottomAnchor.constraint(equalTo: win.bottomAnchor),
            lay.leadingAnchor.constraint(equalTo: win.leadingAnchor),
            lay.trailingAnchor.constraint(equalTo: win.trailingAnchor),
            pw.topAnchor.constraint(equalTo: lay.safeAreaLayoutGuide.topAnchor),
            pw.bottomAnchor.constraint(equalTo: lay.safeAreaLayoutGuide.bottomAnchor),
            pw.leadingAnchor.constraint(equalTo: lay.leadingAnchor),
            pw.trailingAnchor.constraint(equalTo: lay.trailingAnchor),
            x.widthAnchor.constraint(equalToConstant: 44),
            x.heightAnchor.constraint(equalToConstant: 44),
            x.topAnchor.constraint(equalTo: lay.safeAreaLayoutGuide.topAnchor, constant: 12),
            x.trailingAnchor.constraint(equalTo: lay.trailingAnchor, constant: -12)
        ])

        layer = lay
        popup = pw
        return pw
    }

    @objc func closeTapped() {
        closePopup()
    }

    func closePopup() {
        popup?.stopLoading()
        popup?.removeFromSuperview()
        layer?.removeFromSuperview()
        popup = nil
        layer = nil
    }
}

// MARK: - Fenetre "Abonne-toi a la chaine" (premier lancement, bloquante)

final class HesGateViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .light
        view.backgroundColor = UIColor.black.withAlphaComponent(0.7)

        let card = UIView()
        card.backgroundColor = .white
        card.layer.cornerRadius = 30
        card.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(card)

        let title = UILabel()
        title.text = "Abonne-toi \u{00E0} la cha\u{00EE}ne !"
        title.textColor = .black
        title.font = UIFont.boldSystemFont(ofSize: 26)
        title.textAlignment = .center
        title.numberOfLines = 0

        let para = NSMutableParagraphStyle()
        para.alignment = .center
        para.lineHeightMultiple = 1.2
        let msg = UILabel()
        msg.numberOfLines = 0
        msg.attributedText = NSAttributedString(
            string: "Rejoins notre cha\u{00EE}ne WhatsApp pour ne rien rater : nouveaut\u{00E9}s, mises \u{00E0} jour et nouveaux fichiers. Appuie sur le bouton ci-dessous pour continuer ! \u{1F447}",
            attributes: [
                .font: UIFont.systemFont(ofSize: 17),
                .foregroundColor: UIColor(white: 0.267, alpha: 1),
                .paragraphStyle: para
            ])

        let btn = UIButton(type: .custom)
        btn.setTitle("S\u{2019}abonner maintenant", for: .normal)
        btn.setTitleColor(.white, for: .normal)
        btn.titleLabel?.font = UIFont.boldSystemFont(ofSize: 17)
        btn.backgroundColor = UIColor(red: 25.0 / 255.0, green: 118.0 / 255.0, blue: 210.0 / 255.0, alpha: 1)
        btn.layer.cornerRadius = 25
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.addTarget(self, action: #selector(tapped), for: .touchUpInside)

        let wrap = UIView()
        wrap.addSubview(btn)
        NSLayoutConstraint.activate([
            btn.heightAnchor.constraint(equalToConstant: 50),
            btn.topAnchor.constraint(equalTo: wrap.topAnchor),
            btn.bottomAnchor.constraint(equalTo: wrap.bottomAnchor),
            btn.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 16),
            btn.trailingAnchor.constraint(equalTo: wrap.trailingAnchor, constant: -16)
        ])

        let stack = UIStackView(arrangedSubviews: [title, msg, wrap])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 0
        stack.setCustomSpacing(14, after: title)
        stack.setCustomSpacing(26, after: msg)
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        let w = card.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.9)
        w.priority = .defaultHigh
        NSLayoutConstraint.activate([
            w,
            card.widthAnchor.constraint(lessThanOrEqualToConstant: 420),
            card.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 34),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -28),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -24)
        ])
    }

    @objc private func tapped() {
        UserDefaults.standard.set(true, forKey: "wa_follow")
        if let url = URL(string: hesChannelURL) {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
        dismiss(animated: true, completion: nil)
    }
}

// MARK: - Ecran principal (remplace CAPBridgeViewController dans le storyboard)

@objc(HesViewController)
class HesViewController: CAPBridgeViewController {
    private var proxy: HesWebProxy?
    private var gateDone = false

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        installProxy()
        showFollowGate()
    }

    private func installProxy() {
        guard proxy == nil, let wv = bridge?.webView else { return }
        let p = HesWebProxy(host: self)
        p.origNav = wv.navigationDelegate
        p.origUI = wv.uiDelegate
        wv.navigationDelegate = p
        wv.uiDelegate = p
        wv.allowsBackForwardNavigationGestures = true
        proxy = p
    }

    private func showFollowGate() {
        if gateDone || UserDefaults.standard.bool(forKey: "wa_follow") { return }
        gateDone = true
        let g = HesGateViewController()
        g.modalPresentationStyle = .overFullScreen
        g.modalTransitionStyle = .crossDissolve
        g.isModalInPresentation = true
        present(g, animated: true, completion: nil)
    }
}
