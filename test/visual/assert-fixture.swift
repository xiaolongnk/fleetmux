#!/usr/bin/env swift

import AppKit
import Foundation
import Vision

guard CommandLine.arguments.count == 3 else {
    fputs("usage: assert-fixture.swift <image> <sentinel>\n", stderr)
    exit(64)
}

let imagePath = CommandLine.arguments[1]
let sentinel = CommandLine.arguments[2].uppercased()
guard let image = NSImage(contentsOfFile: imagePath),
      let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fputs("fixture assertion FAILED: could not read captured image\n", stderr)
    exit(1)
}

let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
request.usesLanguageCorrection = false

do {
    try VNImageRequestHandler(cgImage: cgImage).perform([request])
} catch {
    fputs("fixture assertion FAILED: Vision OCR could not inspect capture\n", stderr)
    exit(1)
}

let recognized = (request.results ?? [])
    .compactMap { $0.topCandidates(1).first?.string.uppercased() }
    .joined(separator: " ")
guard recognized.contains(sentinel) else {
    fputs("fixture assertion FAILED: capture is not the fixture terminal (sentinel not found)\n", stderr)
    exit(1)
}

print("fixture sentinel PASS")
