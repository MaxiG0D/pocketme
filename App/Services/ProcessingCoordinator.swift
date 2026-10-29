import Foundation
import SwiftData
import Observation

/// One article's offline state, observed on its own so that a download starting or finishing redraws that row only.
/// A shared set would invalidate every row that reads it each time any article changed.
@MainActor @Observable
final class ArticleOfflineState {
    fileprivate(set) var downloading = false
    fileprivate(set) var ready = false
}

@MainActor @Observable
final class ProcessingCoordinator {
    /// Read by the reader, which opens a single article; rows use `state(for:)`.
    private(set) var offlineReady: Set<UUID> = []
    @ObservationIgnored private var states: [UUID: ArticleOfflineState] = [:]
    /// Articles whose offline copy is verified and whose thumbnail has been dealt with: later passes skip them untouched.
    @ObservationIgnored private var settled: Set<UUID> = []
    @ObservationIgnored private var thumbnailTried: Set<UUID> = []
    @ObservationIgnored private var assetFailures: [UUID: Int] = [:]
    @ObservationIgnored private var knownIDs: Set<UUID> = []
    /// Set by the store: true while the library is being scrolled, so background work waits for the finger.
    @ObservationIgnored var shouldPause: () -> Bool = { false }
    /// Set by the store: batches writes instead of saving after every article.
    @ObservationIgnored var requestSave: (() -> Void)?
    let assets: OfflineAssetStore
    private let context: ModelContext
    private let extractor = ExtractionService()
    private let thumbnails = ThumbnailService()
    @ObservationIgnored private var work: Task<Void, Never>?
    @ObservationIgnored private var retry: Task<Void, Never>?
    private var rerun = false
    private var imageCandidates: [UUID: [String]] = [:]
    private var assetRetry: [UUID: Date] = [:]
    private var revisitedVideos = false

    func state(for id: UUID) -> ArticleOfflineState {
        if let state = states[id] { return state }
        let state = ArticleOfflineState()
        states[id] = state
        return state
    }
    private func setDownloading(_ id: UUID, _ value: Bool) { if state(for: id).downloading != value { state(for: id).downloading = value } }
    private func setReady(_ id: UUID, _ value: Bool) {
        if state(for: id).ready != value { state(for: id).ready = value }
        if value { offlineReady.insert(id) } else { offlineReady.remove(id) }
    }
    private func commit() { if let requestSave { requestSave() } else { try? context.save() } }
    /// Lets the UI run between articles and holds still while the list is moving.
    private func yieldToUI() async {
        await Task.yield()
        var waited = 0
        while shouldPause(), waited < 120, !Task.isCancelled { try? await Task.sleep(for: .milliseconds(400)); waited += 1 }
    }

    init(context: ModelContext, root: URL) {
        self.context = context
        assets = OfflineAssetStore(root: root)
    }

    func start() {
        if work != nil { rerun = true; return }
        retry?.cancel()
        work = Task { [weak self] in
            guard let self else { return }
            repeat { self.rerun = false; await self.process() } while self.rerun && !Task.isCancelled
            self.work = nil
            await self.scheduleRetry()
        }
    }

    func finishPendingWork() async {
        start()
        await work?.value
        // A background run may be suspended soon after; do not leave batched writes waiting.
        try? context.save()
    }

    func cancel() { work?.cancel(); retry?.cancel() }

    private func process() async {
        guard let articles = try? context.fetch(FetchDescriptor<Article>(sortBy: [SortDescriptor(\.savedAt)])) else { return }
        if !revisitedVideos {
            // Videos saved before oEmbed support failed as web pages; give them a fresh start once per launch.
            revisitedVideos = true
            for article in articles where article.status == .failed && VideoLink(article.url) != nil {
                article.status = .pending; article.extractionAttempts = 0
            }
        }
        // Text first, newest save first: an article is readable before any image downloads start.
        // Only articles that need extraction cost anything here; the rest are skipped before any await.
        for article in articles.reversed() {
            guard article.modelContext != nil else { continue }
            if Task.isCancelled { return }
            guard article.status == .failed || article.status == .pending else { continue }
            await yieldToUI()
            if article.status == .failed {
                guard article.extractionAttempts <= 3,
                      await assets.retryDate(article.id, attempts: article.extractionAttempts, fallback: article.savedAt) <= .now else { continue }
                article.status = .pending
            }
            if article.status == .pending { await extract(article) }
        }
        // Then offline copies and thumbnails. An article settles once both are done and is never looked at again this
        // launch, so repeat passes (every sync, every return to the app) cost a walk over the list and nothing more.
        for article in articles.reversed() {
            guard article.modelContext != nil else { continue }
            if Task.isCancelled { return }
            let id = article.id
            guard article.status == .ready, !settled.contains(id) else { continue }
            await yieldToUI()
            guard article.contentHTML != nil else { settled.insert(id); continue }
            if article.thumbnailData == nil, thumbnailTried.insert(id).inserted { await fillThumbnail(article) }
            let snapshot = ArticleContent(article)
            if await assets.isReady(snapshot) { setReady(id, true); settled.insert(id); continue }
            guard (assetRetry[id] ?? .distantPast) <= .now else { continue }
            setDownloading(id, true)
            do {
                try await assets.prepare(snapshot)
                if article.modelContext != nil { setReady(id, true); settled.insert(id) }
                else { try? await assets.delete(id) }
                assetRetry[id] = nil; assetFailures[id] = nil
            } catch {
                // Back off 1, 2, 4 ... minutes up to an hour instead of retrying every minute forever.
                let failures = assetFailures[id, default: 0]
                assetFailures[id] = failures + 1
                assetRetry[id] = Date.now.addingTimeInterval(min(3_600, 60 * pow(2, Double(min(failures, 6)))))
            }
            setDownloading(id, false)
        }
        // Reader/offline work finishes first; preview enrichment must not delay reading.
        for article in articles where article.modelContext != nil {
            if Task.isCancelled { return }
            let id = article.id
            guard !thumbnailTried.contains(id) else { continue }
            if article.thumbnailData != nil { thumbnailTried.insert(id); continue }
            thumbnailTried.insert(id)
            await yieldToUI()
            await fillThumbnail(article)
        }
        imageCandidates.removeAll()
        let ids = Set(articles.filter { $0.modelContext != nil }.map(\.id))
        for id in offlineReady.subtracting(ids) { setReady(id, false) }
        assetRetry = assetRetry.filter { ids.contains($0.key) }
        // Removing files of deleted articles is only needed when the set of articles changed.
        if ids != knownIDs { knownIDs = ids; try? await assets.purgeOrphans(keeping: ids) }
    }

    private func extract(_ article: Article) async {
        guard let url = URL(string: article.url) else { article.status = .failed; return }
        setDownloading(article.id, true)
        defer { setDownloading(article.id, false) }
        article.extractionAttempts += 1
        commit()
        do {
            let video = VideoLink(article.url)
            let result: ExtractedArticle
            if let video { result = try await VideoMetadata.fetch(video) } else { result = try await extractor.extract(url: url) }
            guard article.modelContext != nil else { return }
            // The page preview grabbed before oEmbed support is replaced by the video's own thumbnail.
            if video != nil, result.leadImageURL != article.leadImageURL { article.thumbnailData = nil }
            article.title = result.title
            article.siteName = result.siteName.isEmpty ? (url.host() ?? "Website") : result.siteName
            article.author = result.author; article.excerpt = result.excerpt
            article.leadImageURL = result.leadImageURL
            imageCandidates[article.id] = result.imageCandidates
            article.contentHTML = result.content.map { Data($0.utf8) }
            article.wordCount = result.wordCount
            article.readingMinutes = result.isExternal == true ? 0 : result.readingMinutes
            article.status = .ready; article.failureReason = nil
            // New content: the offline copy and the thumbnail check start again for this article.
            settled.remove(article.id); setReady(article.id, false)
            commit()
        } catch is CancellationError {
            article.extractionAttempts = max(0, article.extractionAttempts - 1)
            commit()
        }
        catch {
            guard article.modelContext != nil else { return }
            article.status = .failed
            article.failureReason = "This page couldn’t be loaded. Try again or open the original."
            commit()
            try? await assets.recordFailure(article.id)
        }
    }

    private func fillThumbnail(_ article: Article) async {
        let key = "thumbnailAttempt.v2.\(article.id.uuidString)"
        let defaults = UserDefaults.standard
        if let last = defaults.object(forKey: key) as? Date, Date.now.timeIntervalSince(last) < 86_400 { return }
        guard let page = URL(string: article.url), ["http", "https"].contains(page.scheme ?? "") else { return }
        let html = article.contentHTML.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        let candidates = (imageCandidates[article.id] ?? []) + [article.leadImageURL].compactMap { $0 } + HTMLAssets.images(in: html)
        var seen = Set<String>()
        for candidate in candidates where seen.insert(candidate).inserted {
            guard !Task.isCancelled, article.modelContext != nil else { return }
            guard seen.count <= 8 else { break }
            if let url = URL(string: candidate), let data = try? await thumbnails.thumbnail(from: url) {
                article.thumbnailData = data
                article.leadImageURL = candidate
                commit()
                defaults.removeObject(forKey: key)
                return
            }
        }
        guard !Task.isCancelled, article.modelContext != nil else { return }
        let metadata = await ThumbnailMetadata().image(for: page)
        guard !Task.isCancelled, article.modelContext != nil else { return }
        if let metadata, let data = try? await thumbnails.downsample(metadata) {
            article.thumbnailData = data
            commit()
            defaults.removeObject(forKey: key)
        } else {
            defaults.set(Date.now, forKey: key)
        }
    }

    private func scheduleRetry() async {
        let failed = ArticleStatus.failed.rawValue
        let descriptor = FetchDescriptor<Article>(predicate: #Predicate { $0.statusRaw == failed && $0.extractionAttempts <= 3 })
        guard !Task.isCancelled, let articles = try? context.fetch(descriptor) else { return }
        var dates = Array(assetRetry.values)
        for article in articles {
            dates.append(await assets.retryDate(article.id, attempts: article.extractionAttempts, fallback: article.savedAt))
        }
        guard let next = dates.min() else { return }
        retry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(1, next.timeIntervalSinceNow)))
            guard !Task.isCancelled else { return }
            self?.start()
        }
    }
}
