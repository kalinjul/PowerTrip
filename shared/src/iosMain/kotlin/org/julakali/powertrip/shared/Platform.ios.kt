package org.julakali.powertrip.shared

import platform.UIKit.UIDevice

actual fun platformName(): String {
    val device = UIDevice.currentDevice
    return "${device.systemName} ${device.systemVersion}"
}
