import Foundation

struct DocumentRecord: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var filename: String
    var dateAdded: Date
    var lastPosition: Int
    var pageCount: Int

    init(id: UUID = UUID(), title: String, filename: String, dateAdded: Date = .now, lastPosition: Int = 0, pageCount: Int = 0) {
        self.id = id
        self.title = title
        self.filename = filename
        self.dateAdded = dateAdded
        self.lastPosition = lastPosition
        self.pageCount = pageCount
    }
}
