import Foundation

@main
struct AgentNavigationLayoutTests {
    static func main() throws {
        try testAgentRowsRelyOnNavigationLinkDisclosureIndicator()
        try testPushedScreensHideTabBarWithoutLeavingReservedSpace()
        print("AgentNavigationLayoutTests passed")
    }

    private static func testAgentRowsRelyOnNavigationLinkDisclosureIndicator() throws {
        let source = try readSource("iosApp/OpenClawRemote/Sources/Views/AgentsTabView.swift")

        try expect(
            !source.contains("Image(systemName: \"chevron.right\")"),
            "Agent rows should not draw a manual chevron because NavigationLink already supplies the disclosure indicator"
        )
    }

    private static func testPushedScreensHideTabBarWithoutLeavingReservedSpace() throws {
        let source = try readSource("iosApp/OpenClawRemote/Sources/Views/EarphoneSharedViews.swift")

        try expect(
            source.contains(".toolbar(.hidden, for: .tabBar)"),
            "iOS 16+ pushed screens should use SwiftUI tab bar hiding so the tab bar safe area is removed"
        )
        try expect(
            source.contains("collapsedTabBarSafeAreaInset"),
            "iOS 15 fallback should collapse the hidden tab bar's reserved bottom safe area"
        )
    }

    private static func readSource(_ relativePath: String) throws -> String {
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() {
            throw TestFailure(message)
        }
    }
}

private struct TestFailure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
