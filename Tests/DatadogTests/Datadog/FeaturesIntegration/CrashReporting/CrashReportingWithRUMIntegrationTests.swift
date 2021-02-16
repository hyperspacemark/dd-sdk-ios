/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class CrashReportingWithRUMIntegrationTests: XCTestCase {
    private let rumEventOutput = RUMEventOutputMock()

    // MARK: - Testing Conditional Uploads

    func testWhenSendingCrashReportCollectedLessThan4HoursAgo_itSendsBothRUMErrorAndRUMViewEvent() throws {
        let secondsIn4Hours: TimeInterval = 4 * 60 * 60

        // Given
        let currentDate: Date = .mockDecember15th2019At10AMUTC()
        let crashDate: Date = currentDate.secondsAgo(.random(in: 0..<secondsIn4Hours))

        let crashReport: DDCrashReport = .mockWith(date: crashDate)
        let crashContext: CrashContext = .mockWith(
            lastTrackingConsent: .granted,
            lastRUMViewEvent: .mockRandomWith(model: RUMViewEvent.mockRandom())
        )

        // When
        let integration = CrashReportingWithRUMIntegration(
            rumEventOutput: rumEventOutput,
            dateProvider: RelativeDateProvider(using: currentDate),
            dateCorrector: DateCorrectorMock(correctionOffset: 0)
        )
        integration.send(crashReport: crashReport, with: crashContext)

        // Then
        XCTAssertEqual(rumEventOutput.recordedEvents.count, 2)
        XCTAssertEqual(try rumEventOutput.recordedEvents(ofType: RUMEvent<RUMErrorEvent>.self).count, 1)
        XCTAssertEqual(try rumEventOutput.recordedEvents(ofType: RUMEvent<RUMViewEvent>.self).count, 1)
    }

    func testWhenSendingCrashReportCollectedMoreThan4HoursAgo_itSendsOnlyRUMError() throws {
        let secondsIn4Hours: TimeInterval = 4 * 60 * 60

        // Given
        let currentDate: Date = .mockDecember15th2019At10AMUTC()
        let crashDate: Date = currentDate.secondsAgo(.random(in: secondsIn4Hours..<TimeInterval.greatestFiniteMagnitude))

        let crashReport: DDCrashReport = .mockWith(date: crashDate)
        let crashContext: CrashContext = .mockWith(
            lastTrackingConsent: .granted,
            lastRUMViewEvent: .mockRandomWith(model: RUMViewEvent.mockRandom())
        )

        // When
        let integration = CrashReportingWithRUMIntegration(
            rumEventOutput: rumEventOutput,
            dateProvider: RelativeDateProvider(using: currentDate),
            dateCorrector: DateCorrectorMock(correctionOffset: 0)
        )
        integration.send(crashReport: crashReport, with: crashContext)

        // Then
        XCTAssertEqual(rumEventOutput.recordedEvents.count, 1)
        XCTAssertEqual(try rumEventOutput.recordedEvents(ofType: RUMEvent<RUMErrorEvent>.self).count, 1)
    }

    func testWhenCrashReportHasUnauthorizedTrackingConsent_itIsNotSent() throws {
        // Given
        let crashReport: DDCrashReport = .mockWith(date: .mockDecember15th2019At10AMUTC())
        let crashContext: CrashContext = .mockWith(
            lastTrackingConsent: [.pending, .notGranted].randomElement()!,
            lastRUMViewEvent: .mockRandomWith(model: RUMViewEvent.mockRandom())
        )

        // When
        let integration = CrashReportingWithRUMIntegration(
            rumEventOutput: rumEventOutput,
            dateProvider: RelativeDateProvider(using: .mockDecember15th2019At10AMUTC()),
            dateCorrector: DateCorrectorMock()
        )
        integration.send(crashReport: crashReport, with: crashContext)

        // Then
        XCTAssertEqual(rumEventOutput.recordedEvents.count, 0)
    }

    func testWhenCrashReportHasNoAssociatedLastRUMViewEvent_itIsNotSent() throws {
        // Given
        let crashReport: DDCrashReport = .mockWith(date: .mockDecember15th2019At10AMUTC())
        let crashContext: CrashContext = .mockWith(
            lastTrackingConsent: .granted,
            lastRUMViewEvent: nil
        )

        // When
        let integration = CrashReportingWithRUMIntegration(
            rumEventOutput: rumEventOutput,
            dateProvider: RelativeDateProvider(using: .mockDecember15th2019At10AMUTC()),
            dateCorrector: DateCorrectorMock()
        )
        integration.send(crashReport: crashReport, with: crashContext)

        // Then
        XCTAssertEqual(rumEventOutput.recordedEvents.count, 0)
    }

    // MARK: - Testing Uploaded Data

    func testWhenSendingRUMViewEvent_itIncludesErrorInformation() throws {
        let lastRUMViewEvent: RUMViewEvent = .mockRandom()

        // Given
        let crashDate: Date = .mockDecember15th2019At10AMUTC()
        let crashReport: DDCrashReport = .mockWith(date: crashDate)
        let crashContext: CrashContext = .mockWith(
            lastTrackingConsent: .granted,
            lastRUMViewEvent: .mockRandomWith(model: lastRUMViewEvent)
        )

        // When
        let dateCorrectionOffset: TimeInterval = .mockRandom()
        let integration = CrashReportingWithRUMIntegration(
            rumEventOutput: rumEventOutput,
            dateProvider: RelativeDateProvider(using: crashDate),
            dateCorrector: DateCorrectorMock(correctionOffset: dateCorrectionOffset)
        )
        integration.send(crashReport: crashReport, with: crashContext)

        // Then
        let sendRUMViewEvent = try rumEventOutput.recordedEvents(ofType: RUMEvent<RUMViewEvent>.self)[0].model

        XCTAssertTrue(
            sendRUMViewEvent.application.id == lastRUMViewEvent.application.id
            && sendRUMViewEvent.session.id == lastRUMViewEvent.session.id
            && sendRUMViewEvent.view.id == lastRUMViewEvent.view.id,
            "The `RUMViewEvent` sent must be linked to the same RUM Session as the last `RUMViewEvent`."
        )
        XCTAssertEqual(
            sendRUMViewEvent.view.crash?.count, 1, "The `RUMViewEvent` must include incremented crash count."
        )
        XCTAssertEqual(
            sendRUMViewEvent.dd.documentVersion,
            lastRUMViewEvent.dd.documentVersion + 1,
            "The `RUMViewEvent` sent must contain incremented document version."
        )
        XCTAssertTrue(
            sendRUMViewEvent.view.isActive == false, "The `RUMViewEvent` must be marked as inactive."
        )
        XCTAssertEqual(
            sendRUMViewEvent.date,
            crashDate.addingTimeInterval(dateCorrectionOffset).timeIntervalSince1970.toInt64Milliseconds,
            "The `RUMViewEvent` sent must include crash date corrected by current correction offset."
        )
    }

    func testWhenSendingRUMErrorEvent_itIncludesCrashInformation() throws {
        let lastRUMViewEvent: RUMViewEvent = .mockRandom()

        // Given
        let crashDate: Date = .mockDecember15th2019At10AMUTC()
        let crashReport: DDCrashReport = .mockWith(
            date: crashDate,
            type: "SIG_CODE (SIG_NAME)",
            message: "Signal details",
            stackTrace: """
            0: stack-trace line 0
            1: stack-trace line 1
            2: stack-trace line 2
            """
        )
        let crashContext: CrashContext = .mockWith(
            lastTrackingConsent: .granted,
            lastRUMViewEvent: .mockRandomWith(model: lastRUMViewEvent)
        )

        // When
        let dateCorrectionOffset: TimeInterval = .mockRandom()
        let integration = CrashReportingWithRUMIntegration(
            rumEventOutput: rumEventOutput,
            dateProvider: RelativeDateProvider(using: crashDate),
            dateCorrector: DateCorrectorMock(correctionOffset: dateCorrectionOffset)
        )
        integration.send(crashReport: crashReport, with: crashContext)

        // Then
        let sendRUMErrorEvent = try rumEventOutput.recordedEvents(ofType: RUMEvent<RUMErrorEvent>.self)[0].model

        XCTAssertTrue(
            sendRUMErrorEvent.application.id == lastRUMViewEvent.application.id
            && sendRUMErrorEvent.session.id == lastRUMViewEvent.session.id
            && sendRUMErrorEvent.view.id == lastRUMViewEvent.view.id,
            "The `RUMErrorEvent` sent must be linked to the same RUM Session as the last `RUMViewEvent`."
        )
        XCTAssertTrue(
            sendRUMErrorEvent.error.isCrash == true, "The `RUMErrorEvent` sent must be marked as crash."
        )
        XCTAssertEqual(
            sendRUMErrorEvent.date,
            crashDate.addingTimeInterval(dateCorrectionOffset).timeIntervalSince1970.toInt64Milliseconds,
            "The `RUMErrorEvent` sent must include crash date corrected by current correction offset."
        )
        XCTAssertEqual(
            sendRUMErrorEvent.error.type,
            "SIG_CODE (SIG_NAME)"
        )
        XCTAssertEqual(
            sendRUMErrorEvent.error.message,
            "Signal details"
        )
        XCTAssertEqual(
            sendRUMErrorEvent.error.stack,
            """
            0: stack-trace line 0
            1: stack-trace line 1
            2: stack-trace line 2
            """
        )
    }
}
