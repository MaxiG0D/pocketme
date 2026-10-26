import Foundation

enum LibrarySection: String, CaseIterable, Identifiable {
    case unread, favorites, archive
    var id: Self { self }
    var title: String { switch self { case .unread: "Unread"; case .favorites: "Favorites"; case .archive: "Archive" } }
    var icon: String { switch self { case .unread: "book"; case .favorites: "bookmark"; case .archive: "archivebox" } }
    func includes(_ article: Article) -> Bool {
        switch self { case .unread: article.archivedAt == nil; case .favorites: article.isFavorite; case .archive: article.archivedAt != nil }
    }
}
