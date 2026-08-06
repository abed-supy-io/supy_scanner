// macOS Vision OCR CLI for the DSQ bench CER lane. Host tool only — the
// scanning path never does OCR through this (and never does cloud OCR at
// all, per CLAUDE.md). Prints one line per recognized text observation.
//
// Build: swiftc -O -o build/dsq-bench/vision_ocr tools/bench/ocr/vision_ocr.swift
// Usage: vision_ocr <image-path>

import AppKit
import Foundation
import Vision

func fail(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(2)
}

guard CommandLine.arguments.count == 2 else {
    fail("usage: vision_ocr <image-path>")
}

let path = CommandLine.arguments[1]
guard let image = NSImage(contentsOfFile: path),
      let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
else {
    fail("vision_ocr: cannot load image at \(path)")
}

let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
request.usesLanguageCorrection = false

let handler = VNImageRequestHandler(cgImage: cgImage)
do {
    try handler.perform([request])
} catch {
    fail("vision_ocr: recognition failed: \(error)")
}

for observation in request.results ?? [] {
    if let candidate = observation.topCandidates(1).first {
        print(candidate.string)
    }
}
