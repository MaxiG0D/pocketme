import SafariServices

private struct ContextBox: @unchecked Sendable {
    let context: NSExtensionContext
}

final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        let item = context.inputItems.first as? NSExtensionItem
        let message = item?.userInfo?[SFExtensionMessageKey] as? [String: Any]
        let url = message?["url"] as? String
        let title = (message?["title"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let box = ContextBox(context: context)
        Task {
            var saved = false
            if let url, let queue = try? SaveQueue() {
                saved = (try? await queue.append(url: url, title: title)) != nil
            }
            let response = NSExtensionItem()
            response.userInfo = [SFExtensionMessageKey: ["saved": saved]]
            box.context.completeRequest(returningItems: [response])
        }
    }
}
