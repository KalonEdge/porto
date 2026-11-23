// Checks an update archive's Sparkle signature against the public key the app
// ships with, so a release never goes out signed by the wrong Keychain key.
//
//   swift scripts/verify-update-signature.swift <public key> <archive> <sign_update output>
import CryptoKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 4 else {
    FileHandle.standardError.write(Data("usage: verify-update-signature.swift <public key> <archive> <signature>\n".utf8))
    exit(64)
}
// sign_update -p prints just the base64 signature; accept its full output too.
let printed = arguments[3]
let signatureText = printed.range(of: #"sparkle:edSignature="([^"]+)""#, options: .regularExpression)
    .map { String(printed[$0].dropFirst(21).dropLast()) } ?? printed.trimmingCharacters(in: .whitespacesAndNewlines)

guard let keyData = Data(base64Encoded: arguments[1]), let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData) else {
    FileHandle.standardError.write(Data("The public key isn't a base64 Ed25519 key.\n".utf8))
    exit(1)
}
guard let signature = Data(base64Encoded: signatureText) else {
    FileHandle.standardError.write(Data("The signature isn't base64.\n".utf8))
    exit(1)
}
guard let archive = FileManager.default.contents(atPath: arguments[2]) else {
    FileHandle.standardError.write(Data("Can't read \(arguments[2]).\n".utf8))
    exit(1)
}
guard key.isValidSignature(signature, for: archive) else {
    FileHandle.standardError.write(Data("The archive's signature doesn't match the app's public key. Check SPARKLE_PUBLIC_KEY and the signing key.\n".utf8))
    exit(1)
}
print("Update signature matches the app's public key.")
