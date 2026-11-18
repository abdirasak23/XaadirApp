import Flutter
import UIKit
import LocalAuthentication
import Security

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let registrar = self.registrar(forPlugin: "XaadirBiometric") {
      XaadirBiometric.shared.attach(messenger: registrar.messenger())
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

/// Face ID / Touch ID bound signing key (Secure Enclave, P-256).
///  - biometryCurrentSet: adding or changing a face/finger kills the key (NOT biometryAny)
///  - NO devicePasscode flag, fallback button hidden: no PIN fallback anywhere
///  - The signing call itself shows the Face ID prompt (no separate evaluatePolicy step)
final class XaadirBiometric {
  static let shared = XaadirBiometric()

  private let keyTag = Data("so.xaadir.checkin.key".utf8)
  private var busy = false
  private var channel: FlutterMethodChannel?

  // ASN.1 header: raw P-256 point (65 bytes) -> X.509 SubjectPublicKeyInfo (server uses WebCrypto "spki").
  private let spkiHeader: [UInt8] = [
    0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01,
    0x06, 0x08, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07, 0x03, 0x42, 0x00,
  ]

  func attach(messenger: FlutterBinaryMessenger) {
    let ch = FlutterMethodChannel(name: "xaadir/biometric", binaryMessenger: messenger)
    ch.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result)
    }
    channel = ch
  }

  private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    switch call.method {
    case "status":
      result(status())
    case "createKey":
      createKey(result)
    case "sign":
      let args = call.arguments as? [String: Any]
      sign(
        payload: args?["payload"] as? String,
        reason: (args?["subtitle"] as? String) ?? "Confirm it's you",
        result
      )
    case "deleteKey":
      deleteKey()
      result(true)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // ───────────── status ─────────────
  private func status() -> [String: Any] {
    let ctx = LAContext()
    var err: NSError?
    let can = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err)

    var type = "none"
    switch ctx.biometryType {
    case .faceID: type = "face"
    case .touchID: type = "fingerprint"
    default: type = "none"
    }

    var reason = "OK"
    if !can {
      reason = "UNSUPPORTED"
      if let e = err, let code = LAError.Code(rawValue: e.code) {
        switch code {
        case .biometryNotEnrolled, .passcodeNotSet: reason = "NONE_ENROLLED"
        case .biometryLockout: reason = "HW_UNAVAILABLE"
        case .biometryNotAvailable: reason = "NO_HARDWARE"
        default: reason = "UNSUPPORTED"
        }
      }
    } else if type == "none" {
      reason = "UNSUPPORTED"
    }

    let exists = keyExists()
    return [
      "available": can && type != "none",
      "reason": reason,
      "type": type,
      "keyExists": exists,
      "keyValid": exists,
    ]
  }

  // ───────────── key helpers ─────────────
  private func baseQuery() -> [String: Any] {
    return [
      kSecClass as String: kSecClassKey,
      kSecAttrApplicationTag as String: keyTag,
      kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
    ]
  }

  /// Looks the key up WITHOUT showing any prompt.
  private func keyExists() -> Bool {
    let quiet = LAContext()
    quiet.interactionNotAllowed = true
    var q = baseQuery()
    q[kSecReturnRef as String] = true
    q[kSecUseAuthenticationContext as String] = quiet
    var item: CFTypeRef?
    let s = SecItemCopyMatching(q as CFDictionary, &item)
    return s == errSecSuccess || s == errSecInteractionNotAllowed
  }

  private func loadKey(context: LAContext) -> SecKey? {
    var q = baseQuery()
    q[kSecReturnRef as String] = true
    q[kSecUseAuthenticationContext as String] = context
    var item: CFTypeRef?
    let s = SecItemCopyMatching(q as CFDictionary, &item)
    guard s == errSecSuccess, let item = item else { return nil }
    return (item as! SecKey)
  }

  private func deleteKey() {
    SecItemDelete(baseQuery() as CFDictionary)
  }

  // ───────────── key creation ─────────────
  private func createKey(_ result: @escaping FlutterResult) {
    deleteKey()
    var cfErr: Unmanaged<CFError>?
    guard let access = SecAccessControlCreateWithFlags(
      kCFAllocatorDefault,
      kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
      [.privateKeyUsage, .biometryCurrentSet],
      &cfErr
    ) else {
      result(FlutterError(code: "KEY_ERROR", message: "Access control failed", details: nil))
      return
    }

    let attrs: [String: Any] = [
      kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
      kSecAttrKeySizeInBits as String: 256,
      kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
      kSecPrivateKeyAttrs as String: [
        kSecAttrIsPermanent as String: true,
        kSecAttrApplicationTag as String: keyTag,
        kSecAttrAccessControl as String: access,
      ] as [String: Any],
    ]

    guard let priv = SecKeyCreateRandomKey(attrs as CFDictionary, &cfErr),
          let pub = SecKeyCopyPublicKey(priv),
          let raw = SecKeyCopyExternalRepresentation(pub, &cfErr) as Data?,
          raw.count == 65
    else {
      result(FlutterError(code: "KEY_ERROR", message: "Could not create the Secure Enclave key", details: nil))
      return
    }

    var spki = Data(spkiHeader)
    spki.append(raw)
    result(spki.base64EncodedString())
  }

  // ───────────── error mapping ─────────────
  private func mapLA(_ error: NSError?) -> String {
    guard let e = error, e.domain == LAError.errorDomain,
          let code = LAError.Code(rawValue: e.code) else { return "AUTH_ERROR" }
    switch code {
    case .userCancel, .systemCancel, .appCancel, .userFallback: return "CANCELLED"
    case .biometryLockout: return "LOCKED_OUT"
    case .biometryNotEnrolled, .passcodeNotSet: return "NONE_ENROLLED"
    case .authenticationFailed: return "AUTH_FAILED"
    default: return "AUTH_ERROR"
    }
  }

  // ───────────── signing: the signature call itself shows Face ID / Touch ID ─────────────
  private func sign(payload: String?, reason: String, _ result: @escaping FlutterResult) {
    guard let payload = payload, !payload.isEmpty else {
      result(FlutterError(code: "INVALID_PAYLOAD", message: "Nothing to sign", details: nil))
      return
    }
    if busy {
      result(FlutterError(code: "BUSY", message: "A biometric prompt is already open", details: nil))
      return
    }
    if !keyExists() {
      result(FlutterError(code: "KEY_INVALIDATED", message: "Biometrics changed", details: "no key"))
      return
    }

    busy = true

    let ctx = LAContext()
    ctx.localizedFallbackTitle = ""        // hides "Enter Passcode": no PIN fallback
    ctx.localizedCancelTitle = "Cancel"
    ctx.localizedReason = reason           // text shown with the Face ID / Touch ID prompt

    // Blocks while the system biometric UI is up, so never on the main thread.
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      guard let self = self else { return }

      func finish(_ value: Any) {
        DispatchQueue.main.async {
          self.busy = false
          result(value)
        }
      }

      guard let key = self.loadKey(context: ctx) else {
        finish(FlutterError(code: "KEY_INVALIDATED", message: "Biometrics changed", details: "load nil"))
        return
      }

      var cfErr: Unmanaged<CFError>?
      if let raw = SecKeyCreateSignature(
        key,
        .ecdsaSignatureMessageX962SHA256,
        Data(payload.utf8) as CFData,
        &cfErr
      ) {
        finish((raw as Data).base64EncodedString()) // DER, which the server converts
        return
      }

      let ns: NSError? = cfErr.map { ($0.takeRetainedValue() as Error) as NSError }
      let domain = ns?.domain ?? ""
      let status = ns?.code ?? 0
      let detail = "\(domain) \(status)"

      let code: String
      if domain == LAError.errorDomain {
        code = self.mapLA(ns)                       // cancel / lockout / face not recognised
      } else {
        switch status {
        case -128: code = "CANCELLED"               // errSecUserCanceled
        case -25293: code = "SIGN_AUTH"             // errSecAuthFailed
        case -25300: code = "KEY_INVALIDATED"       // errSecItemNotFound
        case -25308: code = "AUTH_ERROR"            // errSecInteractionNotAllowed
        default: code = "SIGN_FAILED"
        }
      }
      finish(FlutterError(code: code, message: ns?.localizedDescription ?? "Signing failed", details: detail))
    }
  }
}