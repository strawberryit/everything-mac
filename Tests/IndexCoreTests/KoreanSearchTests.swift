import XCTest
@testable import IndexCore

final class KoreanSearchTests: XCTestCase {
    func testKoreanQueriesMatchBothNormalizationForms() {
        var store = FileStore()
        let id = store.append(name: "한글 문서.txt".decomposedStringWithCanonicalMapping,
                              parent: FileStore.noParent, size: 0, mtime: 0,
                              isDir: false, volID: 0)
        store.append(name: "english.txt", parent: FileStore.noParent, size: 0,
                     mtime: 0, isDir: false, volID: 0)
        let composedID = store.append(name: "다른파일.txt", parent: FileStore.noParent,
                                      size: 0, mtime: 0, isDir: false, volID: 0)
        let jamoID = store.append(name: "ㅎ.txt", parent: FileStore.noParent,
                                  size: 0, mtime: 0, isDir: false, volID: 0)
        let engine = QueryEngine()

        for text in ["한글", "한*txt", "한글 문서"] {
            XCTAssertEqual(engine.search(Query(text: text), in: store), [id], text)
        }
        XCTAssertEqual(engine.search(Query(text: "한글", wholeWord: true), in: store), [id])
        XCTAssertEqual(engine.search(Query(text: "다른".decomposedStringWithCanonicalMapping), in: store),
                       [composedID])
        XCTAssertEqual(engine.search(Query(text: "ㅎ"), in: store), [jamoID])
    }

    func testKoreanSearchAfterCacheLoadAndLiveChanges() throws {
        var store = FileStore()
        let oldID = store.append(name: "한글.txt".decomposedStringWithCanonicalMapping,
                                 parent: FileStore.noParent, size: 0, mtime: 0,
                                 isDir: false, volID: 0)
        store = try XCTUnwrap(FileStore(binary: store.serializedBinary()))
        let engine = QueryEngine()
        XCTAssertEqual(engine.search(Query(text: "한글"), in: store), [oldID])

        store.markDeleted(oldID)
        let newID = store.append(name: "한글 새파일.txt", parent: FileStore.noParent,
                                 size: 0, mtime: 0, isDir: false, volID: 0)
        XCTAssertEqual(engine.search(Query(text: "한글"), in: store), [newID])
    }

    func testKoreanPathSearchIncludesASCIIFileNames() {
        var store = FileStore()
        let folderID = store.append(name: "한글폴더", parent: FileStore.noParent,
                                    size: 0, mtime: 0, isDir: true, volID: 0)
        let fileID = store.append(name: "english.txt", parent: folderID,
                                  size: 0, mtime: 0, isDir: false, volID: 0)
        XCTAssertEqual(QueryEngine().search(Query(text: "한글", matchPath: true), in: store),
                       [folderID, fileID])
    }

    func testUnicodeCaseFoldCanMatchASCIIFileName() {
        var store = FileStore()
        let id = store.append(name: "kelvin.txt", parent: FileStore.noParent,
                              size: 0, mtime: 0, isDir: false, volID: 0)
        XCTAssertEqual(QueryEngine().search(Query(text: "K"), in: store), [id])
    }
}
