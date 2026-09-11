#!/usr/bin/env swift

import CoreGraphics
import Foundation

var activeDisplayCount: UInt32 = 0
CGGetActiveDisplayList(0, nil, &activeDisplayCount)
let mainDisplay = CGMainDisplayID()
if activeDisplayCount == 0 || CGDisplayIsActive(mainDisplay) == 0 || CGDisplayIsAsleep(mainDisplay) != 0 {
    fputs("capture FAILED: no active awake display (activeDisplays=\(activeDisplayCount), mainActive=\(CGDisplayIsActive(mainDisplay)), mainAsleep=\(CGDisplayIsAsleep(mainDisplay))); wake the display and retry\n", stderr)
    exit(1)
}
print("display PASS activeDisplays=\(activeDisplayCount) mainActive=1 mainAsleep=0")
