import XCTest
@testable import ESMotionCore
@testable import ESMotionDocument

final class ESMotionDocumentTests: XCTestCase {
    func testEncodingIsDeterministic() throws {
        let document = MotionDocument(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            name: "Deterministic"
        )
        let first = try MotionDocumentCodec.encode(document)
        let second = try MotionDocumentCodec.encode(document)
        XCTAssertEqual(first, second)
    }

    func testRoundTripPreservesDocument() throws {
        let sequence = MotionSequence(name: "Entry", duration: 0.42)
        let document = MotionDocument(
            name: "Round Trip",
            states: [
                MotionState(
                    id: "expanded",
                    name: "Expanded",
                    sequenceIDs: [sequence.id]
                ),
            ],
            sequences: [sequence],
            reducedMotion: MotionAccessibilityFallback(
                staticStateID: "expanded"
            )
        )
        let decoded = try MotionDocumentCodec.decode(
            MotionDocumentCodec.encode(document)
        )
        XCTAssertEqual(decoded, document)
    }

    func testValidatorRejectsEscapingAssetPath() {
        let document = MotionDocument(
            name: "Unsafe",
            assets: [
                MotionAssetDescriptor(
                    id: "unsafe",
                    kind: .image,
                    relativePath: "../secret.png"
                ),
            ]
        )
        let issues = MotionDocumentValidator.validate(document)
        XCTAssertTrue(
            issues.contains {
                $0.severity == .error
                    && $0.path == "assets.unsafe.relativePath"
            }
        )
    }

    func testValidatorFindsMissingSequence() {
        let missingID = UUID()
        let document = MotionDocument(
            name: "Missing",
            states: [
                MotionState(
                    id: "default",
                    name: "Default",
                    sequenceIDs: [missingID]
                ),
            ]
        )
        let issues = MotionDocumentValidator.validate(document)
        XCTAssertTrue(
            issues.contains {
                $0.path == "states.default.sequenceIDs"
                    && $0.severity == .error
            }
        )
    }

    func testArchiveIsDeterministicAndRoundTrips() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(
                path: "ESMotionArchive-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
        let unpacked = FileManager.default.temporaryDirectory
            .appending(
                path: "ESMotionUnpacked-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
        let firstArchive = root.deletingLastPathComponent()
            .appending(path: "\(UUID().uuidString)-1.esmotion")
        let secondArchive = root.deletingLastPathComponent()
            .appending(path: "\(UUID().uuidString)-2.esmotion")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: unpacked)
            try? FileManager.default.removeItem(at: firstArchive)
            try? FileManager.default.removeItem(at: secondArchive)
        }

        let layout = MotionPackageLayout(rootURL: root)
        try layout.prepareDirectories()
        let document = MotionDocument(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            name: "Archive",
            reducedMotion: MotionAccessibilityFallback(
                staticStateID: "default"
            )
        )
        try MotionDocumentCodec.save(document, to: layout.manifestURL)
        try Data("asset".utf8).write(
            to: layout.assetsURL.appending(path: "sample.txt")
        )

        try MotionPackageArchive.pack(
            directory: root,
            to: firstArchive
        )
        try MotionPackageArchive.pack(
            directory: root,
            to: secondArchive
        )
        XCTAssertEqual(
            try Data(contentsOf: firstArchive),
            try Data(contentsOf: secondArchive)
        )

        try MotionPackageArchive.unpack(
            firstArchive,
            to: unpacked
        )
        let decoded = try MotionDocumentCodec.load(
            from: MotionPackageLayout(rootURL: unpacked).manifestURL
        )
        XCTAssertEqual(decoded, document)
    }
}
