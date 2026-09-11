import CryptoKit
import Foundation

// The private key is read from a local file and never printed or passed in argv.
guard CommandLine.arguments.count == 4 else {
    fputs("Usage: swift sign_manifest.swift payload.json private-key-file signed-manifest.json\n", stderr)
    exit(2)
}
let payload = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
let keyText = try String(contentsOfFile: CommandLine.arguments[2], encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
guard let keyData = Data(base64Encoded: keyText) else { throw NSError(domain: "ManifestSigner", code: 1) }
let key = try Curve25519.Signing.PrivateKey(rawRepresentation: keyData)
let envelope = ["payload": payload.base64EncodedString(), "signature": try key.signature(for: payload).base64EncodedString()]
let data = try JSONSerialization.data(withJSONObject: envelope, options: [.prettyPrinted, .sortedKeys])
try data.write(to: URL(fileURLWithPath: CommandLine.arguments[3]), options: .atomic)
print("Public key: " + key.publicKey.rawRepresentation.base64EncodedString())
