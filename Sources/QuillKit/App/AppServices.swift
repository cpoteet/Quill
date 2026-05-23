import Foundation

public final class AppServices: ObservableObject {
    public let database: AppDatabase
    public let draftStore: DraftStore
    public let autosaveStore: AutosaveStore
    public let taxonomyCache: TaxonomyCache

    public init() {
        let db = (try? AppDatabase.production()) ?? (try! AppDatabase.inMemory())
        self.database = db
        self.draftStore = DraftStore(db: db)
        self.autosaveStore = AutosaveStore(db: db)
        self.taxonomyCache = TaxonomyCache(db: db)
    }
}
