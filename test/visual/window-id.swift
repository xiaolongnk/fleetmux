#!/usr/bin/env swift

import CoreGraphics
import Foundation

let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
guard let allWindows = CGWindowListCopyWindowInfo(options, kCGNullWindowID)
        as? [[String: Any]] else {
    fputs("window lookup FAILED: CoreGraphics returned no window list\n", stderr)
    exit(1)
}

let ghosttyWindows = allWindows.filter { window in
    (window[kCGWindowOwnerName as String] as? String) == "Ghostty" &&
    (window[kCGWindowLayer as String] as? Int) == 0
}

func row(_ window: [String: Any]) -> String? {
    guard let windowNumber = window[kCGWindowNumber as String] as? NSNumber,
          let ownerNumber = window[kCGWindowOwnerPID as String] as? NSNumber,
          let boundsValue = window[kCGWindowBounds as String],
          let bounds = CGRect(dictionaryRepresentation: boundsValue as! CFDictionary) else {
        return nil
    }
    let sharing = (window[kCGWindowSharingState as String] as? NSNumber)?.intValue ?? -1
    return "\(windowNumber.intValue)\t\(ownerNumber.intValue)\t\(Int(bounds.width))\t\(Int(bounds.height))\t\(sharing)"
}

if CommandLine.arguments.count == 2 && CommandLine.arguments[1] == "--list" {
    for window in ghosttyWindows {
        if let output = row(window) { print(output) }
    }
    exit(0)
}

guard CommandLine.arguments.count == 3,
      CommandLine.arguments[1] == "--id",
      let wantedID = Int(CommandLine.arguments[2]) else {
    fputs("usage: window-id.swift --list | --id <window-id>\n", stderr)
    exit(64)
}

let matches = ghosttyWindows.filter { window in
    (window[kCGWindowNumber as String] as? NSNumber)?.intValue == wantedID
}
guard matches.count == 1, let output = row(matches[0]) else {
    fputs("window lookup FAILED: expected exactly one visible Ghostty window id \(wantedID), found \(matches.count)\n", stderr)
    exit(1)
}
let fields = output.split(separator: "\t")
let width = Int(fields[2]) ?? 0
let height = Int(fields[3]) ?? 0
let sharing = Int(fields[4]) ?? -1
guard width >= 500, height >= 300 else {
    fputs("window lookup FAILED: fixture terminal bounds are implausible (\(width)x\(height))\n", stderr)
    exit(1)
}
print(output)
