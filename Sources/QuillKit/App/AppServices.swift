import Foundation

public final class AppServices: ObservableObject {
    public let database: AppDatabase
    public let draftStore: DraftStore
    public let autosaveStore: AutosaveStore
    public let taxonomyCache: TaxonomyCache

    /// True when the on-disk database could not be opened and an in-memory fallback is in
    /// use. Local drafts and autosaves will NOT persist across launches in this state — the
    /// UI surfaces this so the user knows their work is at risk rather than failing silently.
    @Published public var storageUnavailable: Bool = false

    public init() {
        let db: AppDatabase
        let unavailable: Bool
        if let production = try? AppDatabase.production() {
            db = production
            unavailable = false
        } else {
            db = try! AppDatabase.inMemory()
            unavailable = true
        }
        self.database = db
        self.draftStore = DraftStore(db: db)
        self.autosaveStore = AutosaveStore(db: db)
        self.taxonomyCache = TaxonomyCache(db: db)
        self.storageUnavailable = unavailable
    }
}
