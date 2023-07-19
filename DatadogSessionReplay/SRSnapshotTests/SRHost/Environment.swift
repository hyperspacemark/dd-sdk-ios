/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

internal struct Environment {
    static func isCI() -> Bool {
        let isCI = Bundle.main.infoDictionary?["IsRunningOnCI"] as? String
        return isCI == "true"
    }
}