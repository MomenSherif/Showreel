import Testing
@testable import ShowreelKit

@Test("Clean titles", arguments: [
    ("Onboarding walkthrough", "Onboarding walkthrough"),
    ("  Pricing   page tour \n", "Pricing page tour"),
    ("", "Untitled Project"),
    ("   ", "Untitled Project"),
])
func cleans(_ input: String, expected: String) {
    #expect(ProjectTitle.clean(input) == expected)
}
