/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Datadog
import DatadogCrashReporting
import UIKit

/// Scenario that launches single-view app which can cause a crash and/or upload the crash report to Datadog.
/// It includes the condition determined by crash report file presence:
/// * if the file is not there, the UI for crashing the app is presented,
/// * if the file is there, the UI for crashing the app is presented and _"Sending crash report..."_ label is shown.
///
/// To test this scenario manually:
///  → disconnect debugger → run the Example app → tap the crash button  → run again to have the crash report uploaded.
final class CrashReportingCollectOrSendScenario: TestScenario {
    static let storyboardName = "CrashReportingScenario"

    let hadPendingCrashReportDataOnStartup: Bool

    init() {
        // The scenario gets instantiated on app startup, so this value is captured
        // before the SDK gets a chance to read & purge the crash report file.
        hadPendingCrashReportDataOnStartup = PersistenceHelpers.hasPendingCrashReportData()
    }

    func configureSDK(builder: Datadog.Configuration.Builder) {
        class CustomPredicate: UIKitRUMViewsPredicate {
            private let defaultPredicate = DefaultUIKitRUMViewsPredicate()

            func rumView(for viewController: UIViewController) -> RUMView? {
                let defaultRUMView = defaultPredicate.rumView(for: viewController)
                return .init(
                    path: defaultRUMView!.path,
                    attributes: [
                        "custom-attribute": "This attribute will be attached to crash report."
                    ]
                )
            }
        }

        _ = builder
            .trackUIKitRUMViews(using: CustomPredicate())
            .enableCrashReporting(using: DDCrashReportingPlugin())
    }
}
