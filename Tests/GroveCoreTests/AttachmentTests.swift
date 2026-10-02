import Testing
import Foundation
import CoreGraphics
import ImageIO
import SQLite3
import UniformTypeIdentifiers
@testable import GroveCore

/// Makes a solid-colour image file in memory.
private func makeImage(width: Int, height: Int, alpha: Bool = false, type: UTType = .png) -> Data {
    let info = alpha ? CGImageAlphaInfo.premultipliedLast.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: info)!
    ctx.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 0.3, alpha: alpha ? 0.5 : 1))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let out = NSMutableData()
    let dest = CGImageDestinationCreateWithData(out, type.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
    return out as Data
}

private func size(of data: Data) -> (Int, Int)? {
    guard let src = CGImageSourceCreateWithData(data as CFData, nil),
          let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
          let w = p[kCGImagePropertyPixelWidth] as? Int, let h = p[kCGImagePropertyPixelHeight] as? Int else { return nil }
    return (w, h)
}

struct ImageToolsTests {
    @Test func smallPngIsKeptAsIs() throws {
        let raw = makeImage(width: 400, height: 300)
        let img = try #require(ImageTools.prepare(raw))
        #expect(img.data == raw)
        #expect(img.mime == "image/png")
        #expect(img.width == 400 && img.height == 300)
    }

    @Test func bigPhotoShrinksToTheLimitAndBecomesJpeg() throws {
        let img = try #require(ImageTools.prepare(makeImage(width: 3200, height: 1600)))
        #expect(img.mime == "image/jpeg")
        #expect(img.width == 1600 && img.height == 800)
        let real = try #require(size(of: img.data))
        #expect(real.0 == 1600 && real.1 == 800)
    }

    @Test func bigImageWithTransparencyStaysPng() throws {
        let img = try #require(ImageTools.prepare(makeImage(width: 2400, height: 3200, alpha: true)))
        #expect(img.mime == "image/png")
        #expect(img.height == 1600 && img.width == 1200)
    }

    @Test func tallImageIsLimitedByItsLongSide() throws {
        let img = try #require(ImageTools.prepare(makeImage(width: 800, height: 3200)))
        #expect(img.height == 1600 && img.width == 400)
    }

    @Test func tiffIsConvertedEvenWhenSmall() throws {
        let img = try #require(ImageTools.prepare(makeImage(width: 100, height: 100, type: .tiff)))
        #expect(img.mime == "image/png" || img.mime == "image/jpeg")
        #expect(img.width == 100 && img.height == 100)
    }

    @Test func notAnImageGivesNil() {
        #expect(ImageTools.prepare(Data("hello".utf8)) == nil)
        #expect(ImageTools.prepare(Data()) == nil)
    }
}

struct AttachmentRepoTests {
    func makeRepos() throws -> Repos { Repos(db: try Database.inMemory()) }

    @Test func addAndGetRoundTrip() throws {
        let r = try makeRepos()
        let raw = makeImage(width: 64, height: 48)
        let a = try #require(try r.attachments.addImage(raw))
        let back = try #require(try r.attachments.get(a.id))
        #expect(back.data == raw)
        #expect(back.mime == "image/png")
        #expect(back.width == 64 && back.height == 48)
        #expect(UUID(uuidString: back.id) != nil)
    }

    @Test func notAnImageIsRefused() throws {
        let r = try makeRepos()
        #expect(try r.attachments.addImage(Data("nope".utf8)) == nil)
        #expect(try r.attachments.count() == 0)
    }

    @Test func getUnknownIdGivesNil() throws {
        #expect(try makeRepos().attachments.get("nope") == nil)
    }

    @Test func deleteRemovesTheRow() throws {
        let r = try makeRepos()
        let a = try #require(try r.attachments.addImage(makeImage(width: 8, height: 8)))
        try r.attachments.delete(a.id)
        #expect(try r.attachments.get(a.id) == nil)
    }

    private func fiveImages(_ r: Repos) throws -> (task: StoredImage, note: StoredImage, event: StoredImage, orphan: StoredImage) {
        func img() throws -> StoredImage { try #require(try r.attachments.addImage(makeImage(width: 8, height: 8))) }
        let (a, b, c, d) = (try img(), try img(), try img(), try img())
        var t = TaskItem(title: "T"); t.notes = ReferenceParser.imageMarkup(id: a.id, alt: "a")
        var n = Note(title: "N"); n.body = "text " + ReferenceParser.imageMarkup(id: b.id, alt: "b")
        var e = EventItem(title: "E", start: WallTime("2026-10-05T09:00")!, end: WallTime("2026-10-05T10:00")!)
        e.notes = ReferenceParser.imageMarkup(id: c.id, alt: "c")
        try r.tasks.save(t); try r.notes.save(n); try r.events.save(e)
        return (a, b, c, d)
    }

    @Test func sweepRemovesOldUnreferencedImagesOnly() throws {
        let r = try makeRepos()
        let x = try fiveImages(r)
        let later = Date().addingTimeInterval(2 * 24 * 3600)
        let removed = try r.attachments.sweepOrphans(olderThanMinutes: 24 * 60, now: later)
        #expect(removed == 1)
        #expect(try r.attachments.get(x.orphan.id) == nil)
        #expect(try r.attachments.get(x.task.id) != nil)
        #expect(try r.attachments.get(x.note.id) != nil)
        #expect(try r.attachments.get(x.event.id) != nil)
    }

    @Test func sweepKeepsFreshImagesEvenWhenNothingUsesThemYet() throws {
        let r = try makeRepos()
        let x = try fiveImages(r)
        #expect(try r.attachments.sweepOrphans(olderThanMinutes: 24 * 60, now: Date()) == 0)
        #expect(try r.attachments.get(x.orphan.id) != nil)
    }

    @Test func imageStaysWhenAnotherBodyStillUsesIt() throws {
        let r = try makeRepos()
        let a = try #require(try r.attachments.addImage(makeImage(width: 8, height: 8)))
        var t1 = TaskItem(title: "One"); t1.notes = ReferenceParser.imageMarkup(id: a.id, alt: "")
        var t2 = TaskItem(title: "Two"); t2.notes = ReferenceParser.imageMarkup(id: a.id, alt: "")
        try r.tasks.save(t1); try r.tasks.save(t2)
        t1.notes = ""
        try r.tasks.save(t1)
        #expect(try r.attachments.sweepOrphans(olderThanMinutes: 0, now: Date().addingTimeInterval(60)) == 0)
    }

    @Test func imagesSurviveTheDailyBackup() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("grove-bk-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let r = try makeRepos()
        let raw = makeImage(width: 32, height: 32)
        let a = try #require(try r.attachments.addImage(raw))
        let file = try #require(try Backup.runDaily(db: r.db, directory: dir, today: DayKey("2026-10-02")))
        let copy = Repos(db: try Database(path: file.path))
        #expect(try copy.attachments.get(a.id)?.data == raw)
    }
}

struct MigrationTwoTests {
    @Test func upgradingAVersionOneDatabaseKeepsItsData() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("grove-m2-\(UUID().uuidString).sqlite").path
        defer { for s in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: path + s) } }
        // Build a version-1 database with the shipped first migration only, then let the app open it.
        var handle: OpaquePointer?
        #expect(sqlite3_open(path, &handle) == SQLITE_OK)
        let seed = Migrations.all[0] + """
            ;PRAGMA user_version = 1;
            INSERT INTO tasks (id, title, created_at, updated_at) VALUES ('t1', 'Old task', '2026-10-01T09:00:00', '2026-10-01T09:00:00');
            """
        #expect(sqlite3_exec(handle, seed, nil, nil, nil) == SQLITE_OK)
        sqlite3_close(handle)
        let r = Repos(db: try Database(path: path))
        #expect(r.db.userVersion == Migrations.all.count)
        #expect(try r.tasks.get("t1")?.title == "Old task")
        #expect(try r.attachments.count() == 0)
    }
}
