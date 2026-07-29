#!/usr/bin/env swift
//
// Cross-language signature check.
//
// The bundle is canonicalised in JavaScript (tools/sign-bundle.mjs) and verified
// in Swift (ios/NoScroll/Core/RuleBundle.swift). If those two disagree by even
// one byte, every bundle fails verification on device and blocking silently
// falls back to whatever is cached — a failure that would not show up in any JS
// test, any Swift test, or the simulator, only on a real user's phone.
//
// So it gets its own check. Run: swift tools/verify-canonical.swift
//
import CryptoKit
import Foundation

// Mirrors RuleStore.canonicalize exactly.
func canonicalize(_ raw: Data) throws -> Data {
    guard var obj = try JSONSerialization.jsonObject(with: raw) as? [String: Any] else {
        throw NSError(domain: "canonical", code: 1)
    }
    obj.removeValue(forKey: "signature")
    return try JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys, .withoutEscapingSlashes])
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let keyURL = root.appendingPathComponent("keys/rules-signing.pub.raw")

guard let keyData = try? Data(contentsOf: keyURL) else {
    print("missing keys/rules-signing.pub.raw — run: node tools/sign-bundle.mjs keygen")
    exit(1)
}
let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: keyData)

var failures = 0
let names = (try? FileManager.default.contentsOfDirectory(atPath: "rules"))?
    .filter { $0.hasSuffix(".json") }
    .map { String($0.dropLast(5)) }
    .sorted() ?? []

for name in names {
    let url = root.appendingPathComponent("rules/\(name).json")
    guard let raw = try? Data(contentsOf: url) else {
        print("FAIL \(name): unreadable"); failures += 1; continue
    }

    // 1. Do Swift and Node produce identical canonical bytes?
    let swiftCanonical = try canonicalize(raw)

    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    proc.arguments = ["node", "tools/sign-bundle.mjs", "canonical", "rules/\(name).json"]
    let pipe = Pipe()
    proc.standardOutput = pipe
    try proc.run()
    let nodeCanonical = pipe.fileHandleForReading.readDataToEndOfFile()
    proc.waitUntilExit()

    if swiftCanonical != nodeCanonical {
        print("FAIL \(name): canonical bytes differ (swift \(swiftCanonical.count)B, node \(nodeCanonical.count)B)")
        failures += 1
        continue
    }

    // 2. Does the signature Node produced verify under Swift's CryptoKit?
    guard let obj = try JSONSerialization.jsonObject(with: raw) as? [String: Any],
          let sigB64 = obj["signature"] as? String,
          let sig = Data(base64Encoded: sigB64)
    else {
        print("FAIL \(name): no signature"); failures += 1; continue
    }

    if publicKey.isValidSignature(sig, for: swiftCanonical) {
        print("OK   \(name): canonical bytes match (\(swiftCanonical.count)B) and signature verifies in CryptoKit")
    } else {
        print("FAIL \(name): signature does not verify in Swift")
        failures += 1
    }
}

exit(failures == 0 ? 0 : 1)
