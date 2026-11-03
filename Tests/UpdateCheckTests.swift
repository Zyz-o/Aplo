#if SWIFT_PACKAGE
import XCTest
@testable import Aplo

final class UpdateCheckTests: XCTestCase {
    func testSelectsNewestPublishedCompatiblePackageNumerically() throws {
        let data = Data("""
        [
          {"tag_name":"v3.9.0","draft":false,"prerelease":false,"assets":[{"name":"Aplo-3.9.0-macOS-arm64.zip","state":"uploaded"}]},
          {"tag_name":"v3.10.0","draft":false,"prerelease":true,"assets":[{"name":"Aplo-3.10.0-macOS-arm64.zip","state":"uploaded"}]},
          {"tag_name":"v4.0.0","draft":true,"prerelease":false,"assets":[{"name":"Aplo-4.0.0-macOS-arm64.zip","state":"uploaded"}]},
          {"tag_name":"v5.0.0","draft":false,"prerelease":false,"assets":[]}
        ]
        """.utf8)
        let release = try UpdateCheck.newest(in: data)
        XCTAssertEqual(release.tag_name, "v3.10.0")
        XCTAssertTrue(release.prerelease)
        XCTAssertEqual(release.downloadPage?.host, "github.com")
        XCTAssertThrowsError(try UpdateCheck.newest(in: Data("[]".utf8)))
        XCTAssertNil(UpdateCheck.version("v3.10.0/redirect"))
    }
}
#endif
