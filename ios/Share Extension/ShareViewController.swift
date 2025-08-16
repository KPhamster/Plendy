import UIKit
import Social
import UniformTypeIdentifiers

class ShareViewController: SLComposeServiceViewController {
  let appGroupId = "group.com.plendy.app"

  override func isContentValid() -> Bool { true }

  override func didSelectPost() {
    handleAttachments { [weak self] in
      self?.openHostApp()
      self?.extensionContext?.completeRequest(returningItems: nil)
    }
  }

  private func handleAttachments(completion: @escaping () -> Void) {
    guard let items = extensionContext?.inputItems as? [NSExtensionItem] else { completion(); return }
    var urls: [String] = []
    var texts: [String] = []
    let dispatchGroup = DispatchGroup()

    for item in items {
      for provider in item.attachments ?? [] {

        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
          dispatchGroup.enter()
          provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
            if let url = item as? URL { urls.append(url.absoluteString) }
            else if let str = item as? String { urls.append(str) }
            dispatchGroup.leave()
          }
        } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
          dispatchGroup.enter()
          provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
            if let str = item as? String { texts.append(str) }
            dispatchGroup.leave()
          }
        }
      }
    }

    dispatchGroup.notify(queue: .main) {
      let defaults = UserDefaults(suiteName: self.appGroupId)
      defaults?.set(urls, forKey: "shared_urls")
      defaults?.set(texts, forKey: "shared_texts")
      defaults?.synchronize()
      completion()
    }
  }

  private func openHostApp() {
    let bundleId = Bundle.main.object(forInfoDictionaryKey: "CFBundleIdentifier") as? String ?? ""
    if let url = URL(string: "ShareMedia-\(bundleId)://") { _ = openURL(url) }
  }

  private func openURL(_ url: URL) -> Bool {
    var responder: UIResponder? = self
    let sel = NSSelectorFromString("openURL:")
    while responder != nil {
      if responder?.responds(to: sel) == true { return responder!.perform(sel, with: url) != nil }
      responder = responder?.next
    }
    return false
  }
}
