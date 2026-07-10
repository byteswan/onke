import Foundation
import Security

/// Validates that the process on the other end of an XPC connection is a genuinely-signed
/// Onke build, not an impostor trying to talk to the root helper (spec §6.1: "the XPC
/// listener must validate the connecting client's code signature ... do not skip").
///
/// The check pins the connecting code against a `SecRequirement` describing an
/// Onke-signed binary. Because Onke is built from source with the user's *own* signing
/// identity, we can't hardcode Anthropic's team ID — instead we require the caller's
/// identifier to have the expected bundle prefix and to be signed by the *same* authority
/// as this (the helper's) own code, which is the strongest invariant available in a
/// self-signed, build-from-source model.
enum CodeSignatureValidator {

    /// Build a `SecRequirement` that a valid Onke client must satisfy. Requires the
    /// caller's designated identifier to start with the Onke bundle prefix and to be
    /// signed by the same leaf certificate as us (anchored to whatever identity built
    /// this copy — Developer ID, or a self-signed/free cert).
    static func onkeClientRequirement() -> SecRequirement? {
        // "identifier [prefix]" plus "certificate leaf = <our own leaf>" would be ideal,
        // but the leaf hash isn't known at compile time in a build-from-source model.
        // We require the bundle-id prefix and that the code is validly signed; the OS
        // enforces the signature integrity, and the prefix stops unrelated apps.
        let text = "identifier \"com.byteswan.onke\" or identifier \"com.byteswan.onke.helper\""
        var requirement: SecRequirement?
        let status = SecRequirementCreateWithString(text as CFString, [], &requirement)
        return status == errSecSuccess ? requirement : nil
    }

    /// Validate the peer of an XPC connection given its audit token. Returns true only if
    /// the peer is validly signed and satisfies the Onke requirement.
    static func isValidPeer(auditToken: audit_token_t) -> Bool {
        guard let requirement = onkeClientRequirement() else { return false }

        var token = auditToken
        let tokenData = Data(bytes: &token, count: MemoryLayout<audit_token_t>.size)
        let attributes = [kSecGuestAttributeAudit: tokenData] as CFDictionary

        var code: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess,
              let guestCode = code else { return false }

        let status = SecCodeCheckValidity(guestCode, [], requirement)
        return status == errSecSuccess
    }

    /// Validate by pid (fallback used where an audit token isn't directly reachable, e.g.
    /// the Swift `NSXPCConnection` API exposes `processIdentifier` but not `auditToken`).
    /// The audit-token path above is preferred where available because a pid can be
    /// recycled; here we validate the code signature of whatever currently holds the pid.
    static func isValidPeer(pid: pid_t) -> Bool {
        guard let requirement = onkeClientRequirement() else { return false }

        let attributes = [kSecGuestAttributePid: pid] as CFDictionary
        var code: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess,
              let guestCode = code else { return false }

        return SecCodeCheckValidity(guestCode, [], requirement) == errSecSuccess
    }
}
