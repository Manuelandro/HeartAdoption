import XCTest

final class AdoptionUITests: XCTestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--demo", "--uitesting"]; app.launch(); return app
    }
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<7 {
            guard element.exists else { app.swipeUp(); continue }
            let window = app.windows.firstMatch.frame
            let keyboard = app.keyboards.firstMatch
            let keyboardTop = keyboard.exists && keyboard.frame.minY > window.minY + 100 ? keyboard.frame.minY : window.maxY
            let visibleTop = window.minY + 90
            let visibleBottom = min(window.maxY - 50, keyboardTop - 10)
            let center = element.frame.midY
            if element.isHittable && center > visibleTop && center < visibleBottom { return }
            if center < visibleTop { app.swipeDown() } else { app.swipeUp() }
        }
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
    func testConnectedAccountCanPublishShareAndPersistSession() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--api-url", "http://localhost:8787"]
        app.launch()
        app.tabBars.buttons["You"].tap()
        if app.alerts["Couldn’t finish that"].waitForExistence(timeout: 3) {
            throw XCTSkip("Start the local API to run the connected app workflow.")
        }
        if app.staticTexts["App Integration"].waitForExistence(timeout: 3) {
            let signOut = app.buttons["Sign out"]; reveal(signOut, in: app); signOut.tap()
        }
        let signIn = app.buttons["Sign in or create an account"]
        XCTAssertTrue(signIn.waitForExistence(timeout: 10)); signIn.tap()
        app.buttons["New here? Create an account"].tap()
        let unique = String(UUID().uuidString.prefix(8))
        let password = "Longer-pass-1234"
        let name = app.textFields["authName"]; reveal(name, in: app); name.tap(); name.typeText("App Integration")
        let email = app.textFields["authEmail"]; reveal(email, in: app); email.tap(); email.typeText("ui\(unique)@example.invalid")
        let secret = app.secureTextFields["authPassword"]; reveal(secret, in: app); secret.tap(); secret.typeText(password)
        let submit = app.buttons["authSubmit"]; reveal(submit, in: app); submit.tap()
        XCTAssertTrue(app.staticTexts["App Integration"].waitForExistence(timeout: 20))
        let notNow = app.buttons.matching(NSPredicate(format: "label IN %@", ["Not Now", "Non ora"])).firstMatch
        if notNow.waitForExistence(timeout: 3) { notNow.tap() }
        app.tabBars.buttons["Discover"].tap()
        let create = app.buttons["createPost"]
        if !create.waitForExistence(timeout: 5) { app.tabBars.buttons["Discover"].tap() }
        XCTAssertTrue(create.waitForExistence(timeout: 5)); create.tap()
        XCTAssertTrue(app.buttons["useTestPhoto"].waitForExistence(timeout: 5)); app.buttons["useTestPhoto"].tap()
        let animal = app.textFields["animalName"]; reveal(animal, in: app); animal.tap(); animal.typeText("River\(unique)")
        let city = app.textFields["animalCity"]; reveal(city, in: app); city.tap(); city.typeText("Rome")
        let story = app.descendants(matching: .any).matching(identifier: "animalStory").firstMatch
        reveal(story, in: app); story.tap(); story.typeText("A gentle rescue who is ready to find a loving home.")
        app.buttons["publishPost"].tap()
        XCTAssertTrue(app.staticTexts["A new beginning\nfor River\(unique)."].waitForExistence(timeout: 20))
        app.buttons["Done"].tap()
        let share = app.buttons["Share River\(unique)"]
        XCTAssertTrue(share.waitForExistence(timeout: 15)); reveal(share, in: app); share.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Copy")).firstMatch.waitForExistence(timeout: 8))
        app.terminate(); app.launch()
        app.tabBars.buttons["You"].tap()
        XCTAssertTrue(app.staticTexts["App Integration"].waitForExistence(timeout: 20))
        let delete = app.buttons["Delete account"]; reveal(delete, in: app); delete.tap()
        let currentPassword = app.secureTextFields["Current password"]; currentPassword.tap(); currentPassword.typeText(password)
        let confirm = app.buttons["Permanently delete account"]; reveal(confirm, in: app); confirm.tap()
        XCTAssertTrue(app.buttons["Sign in or create an account"].waitForExistence(timeout: 20))
        let preview = app.buttons["Explore the app preview"]; reveal(preview, in: app); preview.tap()
        let returnLive = app.buttons["returnLiveApp"]; reveal(returnLive, in: app); returnLive.tap()
        XCTAssertTrue(app.buttons["Sign in or create an account"].waitForExistence(timeout: 20))
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
