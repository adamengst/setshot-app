import XCTest
@testable import SetShot

/// The BTM database is a keyed archive of private classes. These tests build archives
/// in both known layouts under the same class names, so the decoder is exercised
/// without reading the real database, which needs Full Disk Access.
final class BackgroundItemsTests: XCTestCase {

    private let user = "1118DB5A-0250-4B68-8C6F-41843A577BE3"

    @objc(BTMTestItem) private final class Item: NSObject, NSCoding {
        let identifier: String, type: Int, disposition: Int
        init(_ identifier: String, type: Int = 16, disposition: Int) {
            self.identifier = identifier; self.type = type; self.disposition = disposition
        }
        init?(coder: NSCoder) { nil }
        func encode(with c: NSCoder) {
            c.encode(identifier, forKey: "identifier")
            c.encode(type, forKey: "type")
            c.encode(disposition, forKey: "disposition")
        }
    }

    @objc(BTMTestUserStore) private final class UserStore: NSObject, NSCoding {
        let records: [Item]
        init(_ records: [Item]) { self.records = records }
        init?(coder: NSCoder) { nil }
        func encode(with c: NSCoder) { c.encode(records as NSArray, forKey: "records") }
    }

    @objc(BTMTestStorage) private final class Storage: NSObject, NSCoding {
        let byUser: [String: [Item]]
        init(_ byUser: [String: [Item]]) { self.byUser = byUser }
        init?(coder: NSCoder) { nil }
        func encode(with c: NSCoder) {
            c.encode(byUser.mapValues { $0 as NSArray } as NSDictionary, forKey: "itemsByUserIdentifier")
        }
    }

    private func archive(_ key: String, _ object: NSObject) -> Data {
        let a = NSKeyedArchiver(requiringSecureCoding: false)
        a.setClassName("ItemRecord", for: Item.self)
        a.setClassName("BTMUserStore", for: UserStore.self)
        a.setClassName("Storage", for: Storage.self)
        a.encode(object, forKey: key)
        a.finishEncoding()
        return a.encodedData
    }

    private let items = [
        Item("16.com.adobe.ARMDC.Communicator", disposition: 0x9),      // enabled, not allowed
        Item("8.com.example.helper", type: 8, disposition: 0xb),         // enabled, allowed
        Item("2.com.example.app", type: 2, disposition: 0xb),            // one app, two records,
        Item("8192.com.example.app", type: 8192, disposition: 0x9),      // one of them off
        Item("Adobe Acrobat Reader DC", type: 0x20, disposition: 0xb),   // developer group
    ]

    func testPerUserLayout() {
        let data = archive("userStore", UserStore(items))
        XCTAssertEqual(BackgroundItems.lines(fromArchive: data, user: nil), [
            "BTM :: com.adobe.ARMDC.Communicator = 0",
            "BTM :: com.example.app = 0",
            "BTM :: com.example.helper = 1",
        ])
    }

    func testSingleFileLayoutReadsOnlyThisUser() {
        let data = archive("store", Storage([
            user: items,
            "7D266959-1286-4E51-8AD3-33BDE0EF8440": [Item("16.com.someone.else", disposition: 0x3)],
        ]))
        XCTAssertEqual(BackgroundItems.lines(fromArchive: data, user: user, domain: "BTM-system"), [
            "BTM-system :: com.adobe.ARMDC.Communicator = 0",
            "BTM-system :: com.example.app = 0",
            "BTM-system :: com.example.helper = 1",
        ])
    }

    func testTheTypeNumberIsDropped() {
        XCTAssertEqual(BackgroundItems.itemKey("2.com.seriflabs.affinitydesigner2"), "com.seriflabs.affinitydesigner2")
        XCTAssertEqual(BackgroundItems.itemKey("com.example.plain"), "com.example.plain")
        XCTAssertEqual(BackgroundItems.itemKey("Unknown Developer"), "Unknown Developer")
    }

    func testAnUnreadableArchiveGivesNothing() {
        XCTAssertEqual(BackgroundItems.lines(fromArchive: Data("not a plist".utf8), user: nil), [])
        XCTAssertEqual(BackgroundItems.lines(fromArchive: archive("somethingElse", UserStore(items)), user: nil), [])
    }

    func testTheNewestFileForThisStoreIsChosen() {
        let names = [
            "BackgroundItems-v16.btm",
            "BackgroundItems-v18.btm",
            "BackgroundItems-v18-\(user).btm",
            "BackgroundItems-v18-7D266959-1286-4E51-8AD3-33BDE0EF8440.btm",
        ]
        let chosen = BackgroundItems.databaseFile(among: names, user: user)
        XCTAssertEqual(chosen?.0, "BackgroundItems-v18-\(user).btm")
        XCTAssertEqual(chosen?.1, true)

        let older = BackgroundItems.databaseFile(among: ["BackgroundItems-v8.btm", "BackgroundItems-v16.btm"], user: user)
        XCTAssertEqual(older?.0, "BackgroundItems-v16.btm")
        XCTAssertEqual(older?.1, false)
    }

    // MARK: - Comparing across the capture change

    private let kb = KnowledgeBase(entries: [], version: 1, updatedAt: nil)

    func testFirstSnapshotWithItemsDoesNotReportThemAllAsAdded() {
        let result = DiffEngine().parse(diffOutput: """
            +BTM :: com.example.helper = 1
            +BTM-system :: com.adobe.ARMDC.Communicator = 0
            """, kb: kb,
            beforeSnapshot: "BTM :: (requires root; run the setshot.sh CLI with --sudo to capture)\n",
            afterSnapshot: "BTM :: com.example.helper = 1\n")
        XCTAssertEqual(result.recognized.count + result.unrecognized.count, 0)
    }

    func testTurningAnItemOffIsReported() {
        let result = DiffEngine().parse(diffOutput: """
            -BTM-system :: com.adobe.ARMDC.Communicator = 1
            +BTM-system :: com.adobe.ARMDC.Communicator = 0
            """, kb: kb,
            beforeSnapshot: "BTM-system :: com.adobe.ARMDC.Communicator = 1\n",
            afterSnapshot: "BTM-system :: com.adobe.ARMDC.Communicator = 0\n")
        XCTAssertEqual(result.unrecognized.count, 1)
    }

    func testANewItemBetweenTwoCapturingSnapshotsIsReported() {
        let result = DiffEngine().parse(diffOutput: """
            +BTM :: com.example.new = 1
            """, kb: kb,
            beforeSnapshot: "BTM :: com.example.helper = 1\n",
            afterSnapshot: "BTM :: com.example.helper = 1\nBTM :: com.example.new = 1\n")
        XCTAssertEqual(result.unrecognized.count, 1)
    }
}
