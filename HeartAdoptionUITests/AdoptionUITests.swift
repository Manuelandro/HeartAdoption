import XCTest

final class AdoptionUITests: XCTestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--demo", "--uitesting"]; app.launch(); return app
    }
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<7 { if element.exists && element.isHittable { return }; app.swipeUp() }
    }
    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    override func setUpWithError() throws { continueAfterFailure = false }

    func testDiscoverLikesAndDetail() {
        let app = launch()
        XCTAssertTrue(app.buttons["like-Milo"].waitForExistence(timeout: 10))
        capture("Discover", app: app)
        app.buttons["like-Milo"].tap()
        app.tabBars.buttons["Liked"].tap()
        XCTAssertTrue(app.staticTexts["Milo"].waitForExistence(timeout: 5))
        app.staticTexts["Milo"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Meet Milo"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Share Milo"].exists)
        capture("Animal detail", app: app)
    }
    func testGlobalSearchFindsAnimalOutsideHomeCountry() {
        let app = launch()
        let search = app.textFields["discoverSearch"]
        XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("Olive")
        XCTAssertTrue(app.staticTexts["Olive"].waitForExistence(timeout: 7))
        XCTAssertTrue(app.staticTexts["Searching across all countries"].exists)
        capture("Cross-country search", app: app)
    }
    func testSharingPostsAndInvitingFriendsUsesSystemSheet() {
        let app = launch()
        let share = app.buttons["Share Milo"]
        reveal(share, in: app); share.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Copy")).firstMatch.waitForExistence(timeout: 8))
        capture("Share an animal", app: app)
        app.terminate(); app.launch()
        app.tabBars.buttons["You"].tap()
        let invite = app.buttons["inviteFriend"]; reveal(invite, in: app); invite.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Copy")).firstMatch.waitForExistence(timeout: 8))
        capture("Invite a friend", app: app)
    }
    func testCountryGroupAndFollow() {
        let app = launch(); app.tabBars.buttons["Countries"].tap()
        XCTAssertTrue(app.staticTexts["Italy"].waitForExistence(timeout: 5))
        app.staticTexts["Italy"].firstMatch.tap()
        XCTAssertTrue(app.buttons["followCountry"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["followCountry"].label.contains("Following"))
        app.buttons["followCountry"].tap()
        XCTAssertTrue(app.buttons["followCountry"].waitForExistence(timeout: 5))
        expectation(for: NSPredicate(format: "label CONTAINS %@", "Follow country"), evaluatedWith: app.buttons["followCountry"])
        waitForExpectations(timeout: 5)
        capture("Country group", app: app)
    }
    func testPublishWithPhotoAndPersistAfterRelaunch() {
        let app = launch()
        app.buttons["createPost"].tap()
        XCTAssertTrue(app.buttons["useTestPhoto"].waitForExistence(timeout: 5)); app.buttons["useTestPhoto"].tap()
        let name = app.textFields["animalName"]; name.tap(); name.typeText("Pepper")
        let city = app.textFields["animalCity"]; reveal(city, in: app); city.tap(); city.typeText("Florence")
        let story = app.descendants(matching: .any).matching(identifier: "animalStory").firstMatch
        reveal(story, in: app); story.tap(); story.typeText("Pepper is a gentle rescue who loves company and is looking for a loving home.")
        app.buttons["publishPost"].tap()
        XCTAssertTrue(app.staticTexts["A new beginning\nfor Pepper."].waitForExistence(timeout: 10))
        capture("Published", app: app)
        app.buttons["Done"].tap(); app.terminate()
        app.launchArguments = ["--demo"]; app.launch()
        XCTAssertTrue(app.staticTexts["Pepper"].waitForExistence(timeout: 10))
    }
    func testAdministratorHasCountryToolsAndCanHidePost() {
        let app = launch(); app.tabBars.buttons["You"].tap()
        let account = app.buttons["sampleAccount"]
        reveal(account, in: app); account.tap()
        app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Sofia")).firstMatch.tap()
        let administration = app.buttons["administration"]
        reveal(administration, in: app); administration.tap()
        XCTAssertTrue(app.buttons["moderate-Milo"].waitForExistence(timeout: 5)); app.buttons["moderate-Milo"].tap()
        expectation(for: NSPredicate(format: "label CONTAINS %@", "Restore"), evaluatedWith: app.buttons["moderate-Milo"])
        waitForExpectations(timeout: 5)
        XCTAssertFalse(app.buttons["moderate-Nori"].exists)
        capture("Country administration", app: app)
    }
}
