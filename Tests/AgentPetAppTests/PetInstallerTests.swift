import XCTest
@testable import agentpet

final class PetInstallerTests: XCTestCase {
    func testSafePathComponentAcceptsPlainFilenames() {
        XCTAssertEqual(PetInstaller.safePathComponent("boba"), "boba")
        XCTAssertEqual(PetInstaller.safePathComponent("cat-1"), "cat-1")
        XCTAssertEqual(PetInstaller.safePathComponent("spritesheet.png"), "spritesheet.png")
    }

    func testSafePathComponentRejectsTraversal() {
        // A malicious pet pack must not be able to escape ~/.agentpet/pets/.
        XCTAssertNil(PetInstaller.safePathComponent("../../../../Library/LaunchAgents/com.evil.plist"))
        XCTAssertNil(PetInstaller.safePathComponent("../evil"))
        XCTAssertNil(PetInstaller.safePathComponent("a/b"))
        XCTAssertNil(PetInstaller.safePathComponent("nested/sheet.png"))
        XCTAssertNil(PetInstaller.safePathComponent("~/.zshrc"))
        XCTAssertNil(PetInstaller.safePathComponent("..\\..\\evil"))
        XCTAssertNil(PetInstaller.safePathComponent(""))
    }
}
