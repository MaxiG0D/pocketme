import Foundation
import SwiftData
import Observation

@MainActor @Observable
final class ProcessingCoordinator {
    private(set) var downloading: Set<UUID> = []
    private(set) var offlineReady: Set<UUID> = []
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
        for article in articles.reversed() {
            guard article.modelContext != nil else { continue }
            if Task.isCancelled { return }
            if article.status == .failed {
                guard article.extractionAttempts <= 3,
                      await assets.retryDate(article.id, attempts: article.extractionAttempts, fallback: article.savedAt) <= .now else { continue }
                article.status = .pending
            }
            if article.status == .pending { await extract(article) }
        }
        for article in articles.reversed() {
            guard article.modelContext != nil else { continue }
            if Task.isCancelled { return }
            guard article.status == .ready, article.contentHTML != nil else { continue }
            let snapshot = ArticleContent(article)
            if await assets.isReady(snapshot) { offlineReady.insert(article.id); continue }
            guard (assetRetry[article.id] ?? .distantPast) <= .now else { continue }
            downloading.insert(article.id)
            do {
                try await assets.prepare(snapshot)
                if article.modelContext != nil { offlineReady.insert(article.id) }
                else { try? await assets.delete(article.id) }
                assetRetry[article.id] = nil
            } catch { assetRetry[article.id] = Date.now.addingTimeInterval(60) }
            downloading.remove(article.id)
        }
        // Reader/offline work finishes first; preview enrichment must not delay reading.
        for article in articles where article.modelContext != nil && article.thumbnailData == nil {
            if Task.isCancelled { return }
            await fillThumbnail(article)
        }
        imageCandidates.removeAll()
        if let current = try? context.fetch(FetchDescriptor<Article>()) {
            let ids = Set(current.map(\.id))
            offlineReady.formIntersection(ids)
            let ready = Set(current.filter { $0.status == .ready && $0.contentHTML != nil }.map(\.id))
            assetRetry = assetRetry.filter { ready.contains($0.key) }
            try? await assets.purgeOrphans(keeping: ids)
        }
    }

    private func extract(_ article: Article) async {
        guard let url = URL(string: article.url) else { article.status = .failed; return }
        downloading.insert(article.id)
        defer { downloading.remove(article.id) }
        article.extractionAttempts += 1
        try? context.save()
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
            try context.save()
        } catch is CancellationError {
            article.extractionAttempts = max(0, article.extractionAttempts - 1)
            try? context.save()
        }
        catch {
            guard article.modelContext != nil else { return }
            article.status = .failed
            article.failureReason = "This page couldn’t be loaded. Try again or open the original."
            try? context.save()
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
                try? context.save()
                defaults.removeObject(forKey: key)
                return
            }
        }
        guard !Task.isCancelled, article.modelContext != nil else { return }
        let metadata = await ThumbnailMetadata().image(for: page)
        guard !Task.isCancelled, article.modelContext != nil else { return }
        if let metadata, let data = try? await thumbnails.downsample(metadata) {
            article.thumbnailData = data
            try? context.save()
            defaults.removeObject(forKey: key)
        } else {
            defaults.set(Date.now, forKey: key)
        }
    }

    private func scheduleRetry() async {
        guard !Task.isCancelled, let articles = try? context.fetch(FetchDescriptor<Article>()) else { return }
        var dates = Array(assetRetry.values)
        for article in articles where article.status == .failed && article.extractionAttempts <= 3 {
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
