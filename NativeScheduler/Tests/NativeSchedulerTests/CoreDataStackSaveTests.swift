import CoreData
import XCTest
@testable import NativeScheduler

@MainActor
final class CoreDataStackSaveTests: XCTestCase {
    func testStoreURLUsesApplicationSupportOutsideSmokeMode() {
        let url = CoreDataStack.resolveStoreURL(
            environment: [:],
            applicationSupportDirectory: URL(fileURLWithPath: "/tmp/support"),
            fileExists: { _ in false }
        )

        XCTAssertEqual(url?.path, "/tmp/support/NativeScheduler/NativeScheduler.sqlite")
    }

    func testStoreURLRejectsSmokeModeWithoutRoot() {
        let url = CoreDataStack.resolveStoreURL(
            environment: ["NATIVE_SCHEDULER_SMOKE_AUTOSTART": "1"],
            applicationSupportDirectory: URL(fileURLWithPath: "/tmp/support"),
            fileExists: { _ in true }
        )

        XCTAssertNil(url)
    }

    func testStoreURLRejectsSmokeModeWithoutSentinel() {
        let root = URL(fileURLWithPath: "/tmp/smoke-root")
        let url = CoreDataStack.resolveStoreURL(
            environment: [
                "NATIVE_SCHEDULER_SMOKE_AUTOSTART": "1",
                "NATIVE_SCHEDULER_SMOKE_STORE_ROOT": root.path
            ],
            applicationSupportDirectory: URL(fileURLWithPath: "/tmp/support"),
            fileExists: { _ in false }
        )

        XCTAssertNil(url)
    }

    func testStoreURLUsesSentinelBackedSmokeRoot() {
        let root = URL(fileURLWithPath: "/tmp/smoke-root")
        let sentinel = root.appendingPathComponent(".native-scheduler-isolated-qa")
        let url = CoreDataStack.resolveStoreURL(
            environment: [
                "NATIVE_SCHEDULER_SMOKE_AUTOSTART": "1",
                "NATIVE_SCHEDULER_SMOKE_STORE_ROOT": root.path
            ],
            applicationSupportDirectory: URL(fileURLWithPath: "/tmp/support"),
            fileExists: { $0 == sentinel.path }
        )

        XCTAssertEqual(url?.path, "/tmp/smoke-root/NativeScheduler.sqlite")
    }

    func testLogDirectoryUsesApplicationSupportOutsideSmokeMode() {
        let url = DailyLogWriter.resolveLogDirectory(
            environment: [:],
            applicationSupportDirectory: URL(fileURLWithPath: "/tmp/support"),
            fileExists: { _ in false }
        )

        XCTAssertEqual(url?.path, "/tmp/support/NativeScheduler/logs")
    }

    func testLogDirectoryUsesSentinelBackedSmokeRoot() {
        let root = URL(fileURLWithPath: "/tmp/smoke-root")
        let sentinel = root.appendingPathComponent(".native-scheduler-isolated-qa")
        let url = DailyLogWriter.resolveLogDirectory(
            environment: [
                "NATIVE_SCHEDULER_SMOKE_AUTOSTART": "1",
                "NATIVE_SCHEDULER_SMOKE_STORE_ROOT": root.path
            ],
            applicationSupportDirectory: URL(fileURLWithPath: "/tmp/support"),
            fileExists: { $0 == sentinel.path }
        )

        XCTAssertEqual(url?.path, "/tmp/smoke-root/logs")
    }

    func testLogDirectoryRejectsSmokeModeWithoutSentinel() {
        let url = DailyLogWriter.resolveLogDirectory(
            environment: [
                "NATIVE_SCHEDULER_SMOKE_AUTOSTART": "1",
                "NATIVE_SCHEDULER_SMOKE_STORE_ROOT": "/tmp/smoke-root"
            ],
            applicationSupportDirectory: URL(fileURLWithPath: "/tmp/support"),
            fileExists: { _ in false }
        )

        XCTAssertNil(url)
    }

    func testLogDirectoryRejectsSmokeModeWithMalformedRoot() {
        let url = DailyLogWriter.resolveLogDirectory(
            environment: [
                "NATIVE_SCHEDULER_SMOKE_AUTOSTART": "1",
                "NATIVE_SCHEDULER_SMOKE_STORE_ROOT": "relative-root"
            ],
            applicationSupportDirectory: URL(fileURLWithPath: "/tmp/support"),
            fileExists: { _ in true }
        )

        XCTAssertNil(url)
    }

    func testSaveCompletesAndPublishesDidSaveBeforeReturning() throws {
        let context = try makeContext()
        let object = NSEntityDescription.insertNewObject(forEntityName: "CategoryEntity", into: context)
        object.setValue(UUID(), forKey: "id")
        object.setValue("Test", forKey: "name")
        object.setValue("#000000", forKey: "colorHex")
        object.setValue(Date(), forKey: "createdAt")
        object.setValue(Int32(0), forKey: "sortOrder")

        var didSaveCount = 0
        let observer = NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextDidSave,
            object: context,
            queue: nil
        ) { _ in
            didSaveCount += 1
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        let result = CoreDataStack.shared.save(context: context)

        XCTAssertNoThrow(try result.get())

        XCTAssertFalse(context.hasChanges, "save(context:) returned before the context finished saving")
        XCTAssertEqual(didSaveCount, 1, "did-save must be published before save(context:) returns")
    }

    func testSaveFailureIsCompleteBeforeReturning() throws {
        let context = try makeContext()
        NSEntityDescription.insertNewObject(forEntityName: "CategoryEntity", into: context)

        let result = CoreDataStack.shared.save(context: context)

        XCTAssertTrue(context.hasChanges, "a failed save must leave the invalid changes observable")
        switch result {
        case .success:
            XCTFail("save(context:) must return the validation failure")
        case let .failure(error):
            let cocoaError = error as NSError
            XCTAssertEqual(cocoaError.domain, NSCocoaErrorDomain)
            XCTAssertEqual(cocoaError.code, NSValidationMultipleErrorsError)
        }
    }

    private func makeContext() throws -> NSManagedObjectContext {
        let container = NSPersistentContainer(
            name: "CoreDataStackSaveTests",
            managedObjectModel: CoreDataStack.model
        )
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [description]

        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }
        return container.viewContext
    }
}
