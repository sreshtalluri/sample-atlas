import Foundation
import CSQLite

public struct CatalogError: LocalizedError {
    public let message: String
    public var errorDescription: String? { message }
}

// A single actor owns this connection. Scanners yield between batches; no SQLite work runs on the UI actor.
public actor Catalog {
    private var db: OpaquePointer?
    public let path: String
    public init(path: String) throws {
        self.path = path
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            throw CatalogError(message: "Cannot open catalog at \(path)")
        }
        sqlite3_busy_timeout(db, 5000)
        let schema = """
        PRAGMA journal_mode=WAL;
        PRAGMA foreign_keys=ON;
        CREATE TABLE IF NOT EXISTS sources(id INTEGER PRIMARY KEY, path TEXT UNIQUE NOT NULL, name TEXT NOT NULL, bookmark BLOB);
        CREATE TABLE IF NOT EXISTS samples(
          id INTEGER PRIMARY KEY, source_id INTEGER NOT NULL REFERENCES sources(id) ON DELETE CASCADE,
          path TEXT UNIQUE NOT NULL, name TEXT NOT NULL, folder TEXT NOT NULL,
          duration REAL NOT NULL, sample_rate REAL NOT NULL, channels INTEGER NOT NULL,
          bpm REAL, musical_key TEXT, category TEXT NOT NULL, tags TEXT NOT NULL DEFAULT '',
          favorite INTEGER NOT NULL DEFAULT 0, available INTEGER NOT NULL DEFAULT 1,
          fingerprint TEXT NOT NULL, metadata_origin TEXT NOT NULL DEFAULT 'filename', seen TEXT NOT NULL DEFAULT ''
        );
        CREATE INDEX IF NOT EXISTS sample_bpm ON samples(bpm);
        CREATE INDEX IF NOT EXISTS sample_key ON samples(musical_key);
        CREATE INDEX IF NOT EXISTS sample_source ON samples(source_id);
        CREATE INDEX IF NOT EXISTS sample_category ON samples(category);
        CREATE VIRTUAL TABLE IF NOT EXISTS sample_fts USING fts5(name, folder, tags, category, content='samples', content_rowid='id', prefix='2 3 4', tokenize='unicode61 remove_diacritics 2');
        CREATE TRIGGER IF NOT EXISTS sample_insert AFTER INSERT ON samples BEGIN
          INSERT INTO sample_fts(rowid,name,folder,tags,category) VALUES(new.id,new.name,new.folder,new.tags,new.category);
        END;
        CREATE TRIGGER IF NOT EXISTS sample_delete AFTER DELETE ON samples BEGIN
          INSERT INTO sample_fts(sample_fts,rowid,name,folder,tags,category) VALUES('delete',old.id,old.name,old.folder,old.tags,old.category);
        END;
        CREATE TRIGGER IF NOT EXISTS sample_update AFTER UPDATE OF name,folder,tags,category ON samples BEGIN
          INSERT INTO sample_fts(sample_fts,rowid,name,folder,tags,category) VALUES('delete',old.id,old.name,old.folder,old.tags,old.category);
          INSERT INTO sample_fts(rowid,name,folder,tags,category) VALUES(new.id,new.name,new.folder,new.tags,new.category);
        END;
        """
        guard sqlite3_exec(db, schema, nil, nil, nil) == SQLITE_OK else {
            let error = String(cString: sqlite3_errmsg(db)); sqlite3_close(db); db = nil
            throw CatalogError(message: error)
        }
        // Additive migration preserves the user's existing catalog and annotations.
        var pragma: OpaquePointer?
        sqlite3_prepare_v2(db, "PRAGMA table_info(samples)", -1, &pragma, nil)
        var columns = Set<String>()
        while sqlite3_step(pragma) == SQLITE_ROW {
            if let name = sqlite3_column_text(pragma, 1) { columns.insert(String(cString: name)) }
        }
        sqlite3_finalize(pragma)
        for (name, type) in [("kind", "TEXT NOT NULL DEFAULT 'Unknown'"), ("root_note", "TEXT"), ("metadata_version", "INTEGER NOT NULL DEFAULT 0")] where !columns.contains(name) {
            guard sqlite3_exec(db, "ALTER TABLE samples ADD COLUMN \(name) \(type)", nil, nil, nil) == SQLITE_OK else {
                throw CatalogError(message: String(cString: sqlite3_errmsg(db)))
            }
        }
        sqlite3_exec(db, "CREATE INDEX IF NOT EXISTS sample_kind ON samples(kind); CREATE INDEX IF NOT EXISTS sample_root_note ON samples(root_note); PRAGMA user_version=2;", nil, nil, nil)
    }
    deinit { sqlite3_close(db) }

    private func statement(_ sql: String, _ values: [Any?] = []) throws -> OpaquePointer {
        var s: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &s, nil) == SQLITE_OK, let s else { throw failure() }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (offset, value) in values.enumerated() {
            let i = Int32(offset + 1)
            switch value {
            case let v as String: sqlite3_bind_text(s, i, v, -1, transient)
            case let v as Int64: sqlite3_bind_int64(s, i, v)
            case let v as Int: sqlite3_bind_int64(s, i, Int64(v))
            case let v as Double: sqlite3_bind_double(s, i, v)
            case let v as Data: _ = v.withUnsafeBytes { sqlite3_bind_blob(s, i, $0.baseAddress, Int32(v.count), transient) }
            default: sqlite3_bind_null(s, i)
            }
        }
        return s
    }
    private func failure() -> CatalogError { CatalogError(message: String(cString: sqlite3_errmsg(db))) }
    private func run(_ sql: String, _ values: [Any?] = []) throws {
        let s = try statement(sql, values); defer { sqlite3_finalize(s) }
        guard sqlite3_step(s) == SQLITE_DONE else { throw failure() }
    }
    private func string(_ s: OpaquePointer, _ i: Int32) -> String { sqlite3_column_text(s, i).map { String(cString: $0) } ?? "" }
    public func addSource(url: URL, bookmark: Data? = nil) throws -> LibrarySource {
        let canonical = url.resolvingSymlinksInPath().standardizedFileURL.path
        // Reject overlapping roots so ownership/removal remains unambiguous.
        for existing in try sources() {
            if canonical == existing.path { return existing }
            if canonical.hasPrefix(existing.path + "/") || existing.path.hasPrefix(canonical + "/") {
                throw CatalogError(message: "This folder overlaps \(existing.name). Add separate roots or use the existing source.")
            }
        }
        try run("INSERT INTO sources(path,name,bookmark) VALUES(?,?,?)", [canonical, url.lastPathComponent, bookmark])
        return LibrarySource(id: sqlite3_last_insert_rowid(db), path: canonical, name: url.lastPathComponent, bookmark: bookmark)
    }
    public func sources() throws -> [LibrarySource] {
        let s = try statement("SELECT id,path,name,bookmark FROM sources ORDER BY name"); defer { sqlite3_finalize(s) }
        var result: [LibrarySource] = []
        while sqlite3_step(s) == SQLITE_ROW {
            let data = sqlite3_column_blob(s, 3).map { Data(bytes: $0, count: Int(sqlite3_column_bytes(s, 3))) }
            result.append(LibrarySource(id: sqlite3_column_int64(s, 0), path: string(s, 1), name: string(s, 2), bookmark: data))
        }
        return result
    }
    public func removeSource(_ id: Int64) throws { try run("DELETE FROM sources WHERE id=?", [id]) }
    public func setFavorite(_ id: Int64, _ value: Bool) throws { try run("UPDATE samples SET favorite=? WHERE id=?", [value ? 1 : 0, id]) }
    public func setTags(_ id: Int64, _ tags: String) throws { try run("UPDATE samples SET tags=? WHERE id=?", [tags, id]) }
    public func fingerprints(sourceID: Int64) throws -> [String: String] {
        let s = try statement("SELECT path,fingerprint FROM samples WHERE source_id=? AND metadata_version=?", [sourceID, Metadata.version]); defer { sqlite3_finalize(s) }
        var result: [String: String] = [:]
        while sqlite3_step(s) == SQLITE_ROW { result[string(s, 0)] = string(s, 1) }
        return result
    }
    public func upsert(_ samples: [Sample], seen: String) throws {
        try run("BEGIN IMMEDIATE")
        do {
            for v in samples {
                try run("""
                INSERT INTO samples(source_id,path,name,folder,duration,sample_rate,channels,bpm,musical_key,category,tags,fingerprint,metadata_origin,seen,kind,root_note,metadata_version)
                VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT(path) DO UPDATE SET
                name=excluded.name,folder=excluded.folder,duration=excluded.duration,sample_rate=excluded.sample_rate,
                channels=excluded.channels,bpm=excluded.bpm,musical_key=excluded.musical_key,category=excluded.category,
                fingerprint=excluded.fingerprint,metadata_origin=excluded.metadata_origin,seen=excluded.seen,available=1,
                kind=excluded.kind,root_note=excluded.root_note,metadata_version=excluded.metadata_version
                """, [v.sourceID,v.path,v.name,v.folder,v.duration,v.sampleRate,v.channels,v.bpm,v.key,v.category,v.tags,v.fingerprint,v.metadataOrigin,seen,v.kind,v.rootNote,Metadata.version])
            }
            try run("COMMIT")
        } catch { try? run("ROLLBACK"); throw error }
    }
    public func markSeen(paths: [String], token: String) throws {
        try run("BEGIN IMMEDIATE")
        do {
            for path in paths { try run("UPDATE samples SET seen=?,available=1 WHERE path=?", [token,path]) }
            try run("COMMIT")
        } catch { try? run("ROLLBACK"); throw error }
    }
    public func finishScan(sourceID: Int64, token: String) throws {
        try run("UPDATE samples SET available=0 WHERE source_id=? AND seen<>?", [sourceID,token])
    }
    public func count() throws -> Int {
        let s = try statement("SELECT count(*) FROM samples"); defer { sqlite3_finalize(s) }
        guard sqlite3_step(s) == SQLITE_ROW else { throw failure() }; return Int(sqlite3_column_int64(s, 0))
    }
    private func filters(_ request: SearchRequest) -> (String, [Any?]) {
        var clauses = ["1=1"]; var values: [Any?] = []
        if !request.includeUnavailable { clauses.append("s.available=1") }
        if let id = request.sourceID { clauses.append("s.source_id=?"); values.append(id) }
        if !request.category.isEmpty { clauses.append("s.category=?"); values.append(request.category) }
        if !request.kind.isEmpty { clauses.append("s.kind=?"); values.append(request.kind) }
        if request.key == "Unknown" { clauses.append("s.musical_key IS NULL") }
        else if request.key.hasPrefix("root:") { clauses.append("s.root_note=?"); values.append(String(request.key.dropFirst(5))) }
        else if !request.key.isEmpty { clauses.append("s.musical_key=?"); values.append(Metadata.normalizeKey(request.key) ?? request.key) }
        if request.unknownBPM { clauses.append("s.bpm IS NULL") }
        else {
            if let min = request.minBPM { clauses.append("s.bpm>=?"); values.append(min) }
            if let max = request.maxBPM { clauses.append("s.bpm<=?"); values.append(max) }
        }
        if request.favoritesOnly { clauses.append("s.favorite=1") }
        return (clauses.joined(separator: " AND "), values)
    }
    public func eligibleIDs(_ request: SearchRequest) throws -> [Int64] {
        let (whereSQL, values) = filters(request)
        let s = try statement("SELECT s.id FROM samples s WHERE \(whereSQL)", values); defer { sqlite3_finalize(s) }
        var ids: [Int64] = []; while sqlite3_step(s) == SQLITE_ROW { ids.append(sqlite3_column_int64(s, 0)) }; return ids
    }
    /// Snapshot just the ranked IDs. Hydrate visible rows in pages, without a result cap
    /// or repeatedly sorting the same FTS matches while the user scrolls.
    public func matchingIDs(_ request: SearchRequest) throws -> [Int64] {
        let (whereSQL, filterValues) = filters(request)
        var values = filterValues
        var sql = "SELECT s.id FROM samples s"
        let query = Metadata.ftsQuery(request.text)
        if query != nil { sql += " JOIN sample_fts ON sample_fts.rowid=s.id" }
        sql += " WHERE " + whereSQL
        if let query { sql += " AND sample_fts MATCH ?"; values.append(query) }
        sql += query == nil ? " ORDER BY s.favorite DESC,s.name COLLATE NOCASE,s.id" : " ORDER BY bm25(sample_fts,8.0,1.0,4.0,3.0),s.id"
        let s = try statement(sql, values); defer { sqlite3_finalize(s) }
        var ids: [Int64] = []
        var step = sqlite3_step(s)
        while step == SQLITE_ROW { ids.append(sqlite3_column_int64(s, 0)); step = sqlite3_step(s) }
        guard step == SQLITE_DONE else { throw failure() }
        return ids
    }
    public func search(_ request: SearchRequest, rankedIDs: [Int64]? = nil) throws -> [Sample] {
        let (whereSQL, filterValues) = filters(request)
        var values = filterValues
        var join = ""; var predicate = whereSQL; var order = "s.favorite DESC,s.name COLLATE NOCASE,s.id"
        if let rankedIDs {
            guard !rankedIDs.isEmpty else { return [] }
            let ids = Array(rankedIDs.dropFirst(max(0, request.offset)).prefix(max(1, min(request.limit, 500))))
            guard !ids.isEmpty else { return [] }
            predicate += " AND s.id IN (" + ids.map { _ in "?" }.joined(separator: ",") + ")"
            values.append(contentsOf: ids.map { $0 as Any? })
        } else if let query = Metadata.ftsQuery(request.text) {
            join = " JOIN sample_fts ON sample_fts.rowid=s.id"
            predicate += " AND sample_fts MATCH ?"; values.append(query)
            order = "bm25(sample_fts,8.0,1.0,4.0,3.0),s.id"
        }
        values.append(max(1, min(request.limit, 500)))
        values.append(rankedIDs == nil ? max(0, request.offset) : 0)
        let s = try statement("SELECT s.id,s.source_id,s.path,s.name,s.folder,s.duration,s.sample_rate,s.channels,s.bpm,s.musical_key,s.category,s.tags,s.favorite,s.available,s.fingerprint,s.metadata_origin,s.kind,s.root_note FROM samples s\(join) WHERE \(predicate) ORDER BY \(order) LIMIT ? OFFSET ?", values)
        defer { sqlite3_finalize(s) }
        var samples: [Sample] = []
        var step = sqlite3_step(s)
        while step == SQLITE_ROW {
            var v = Sample(sourceID: sqlite3_column_int64(s, 1), path: string(s, 2), name: string(s, 3), folder: string(s, 4),
                           duration: sqlite3_column_double(s, 5), sampleRate: sqlite3_column_double(s, 6), channels: Int(sqlite3_column_int(s, 7)),
                           bpm: sqlite3_column_type(s, 8) == SQLITE_NULL ? nil : sqlite3_column_double(s, 8),
                           key: sqlite3_column_type(s, 9) == SQLITE_NULL ? nil : string(s, 9), category: string(s, 10), tags: string(s, 11), fingerprint: string(s, 14))
            v.id = sqlite3_column_int64(s, 0); v.favorite = sqlite3_column_int(s, 12) == 1
            v.available = sqlite3_column_int(s, 13) == 1; v.metadataOrigin = string(s, 15)
            v.kind = string(s, 16); v.rootNote = sqlite3_column_type(s, 17) == SQLITE_NULL ? nil : string(s, 17)
            samples.append(v)
            step = sqlite3_step(s)
        }
        guard step == SQLITE_DONE else { throw failure() }
        if let ids = rankedIDs {
            let ranks = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1,$0) })
            samples.sort { ranks[$0.id, default: .max] < ranks[$1.id, default: .max] }
        }
        return samples
    }
}

public enum HybridRanking {
    // Reciprocal rank fusion avoids pretending BM25 and cosine similarity share a scale.
    public static func fuse(lexical: [Int64], semantic: [Int64], limit: Int = .max) -> [Int64] {
        var scores: [Int64: Double] = [:]
        for (list, weight) in [(lexical, 1.15), (semantic, 1.0)] {
            var seen = Set<Int64>()
            for (rank, id) in list.filter({ seen.insert($0).inserted }).enumerated() {
                scores[id, default: 0] += weight / Double(60 + rank + 1)
            }
        }
        return scores.keys.sorted { scores[$0]! == scores[$1]! ? $0 < $1 : scores[$0]! > scores[$1]! }.prefix(limit).map { $0 }
    }
}
