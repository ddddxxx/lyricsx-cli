import XCTest

#if !canImport(ObjectiveC)
public func allTests() -> [XCTestCaseEntry] {
    return [
        testCase(lyricsx_cliTests.allTests),
    ]
}
#endif
