package com.example.xaadir // <- change to your applicationId / package

import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import android.util.Base64
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricManager.Authenticators.BIOMETRIC_STRONG
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.PrivateKey
import java.security.Signature
import java.security.spec.ECGenParameterSpec

/**
 * Fingerprint-bound signing key (Android Keystore, EC P-256).
 *  - fingerprint ONLY (BIOMETRIC_STRONG, no PIN / pattern / password fallback)
 *  - user authentication required for EVERY signature
 *  - key is permanently invalidated when a fingerprint is added (or all are removed)
 */
class BiometricChannel(
    private val activity: FragmentActivity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "xaadir/biometric"
        private const val KEY_ALIAS = "xaadir_checkin_key"
        private const val ANDROID_KEYSTORE = "AndroidKeyStore"
    }

    private var busy = false

    init {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "status" -> result.success(status())
            "createKey" -> createKey(result)
            "sign" -> sign(
                call.argument<String>("payload"),
                call.argument<String>("title"),
                call.argument<String>("subtitle"),
                result,
            )
            "deleteKey" -> {
                deleteKey()
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    // ───────────── status ─────────────
    private fun status(): Map<String, Any> {
        val code = BiometricManager.from(activity).canAuthenticate(BIOMETRIC_STRONG)
        val reason = when (code) {
            BiometricManager.BIOMETRIC_SUCCESS -> "OK"
            BiometricManager.BIOMETRIC_ERROR_NO_HARDWARE -> "NO_HARDWARE"
            BiometricManager.BIOMETRIC_ERROR_HW_UNAVAILABLE -> "HW_UNAVAILABLE"
            BiometricManager.BIOMETRIC_ERROR_NONE_ENROLLED -> "NONE_ENROLLED"
            BiometricManager.BIOMETRIC_ERROR_SECURITY_UPDATE_REQUIRED -> "UPDATE_REQUIRED"
            else -> "UNSUPPORTED"
        }
        val exists = loadPrivateKey() != null
        return mapOf(
            "available" to (code == BiometricManager.BIOMETRIC_SUCCESS),
            "reason" to reason,
            "keyExists" to exists,
            "keyValid" to (exists && keyValid()),
        )
    }

    private fun keyStore(): KeyStore = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }

    private fun loadPrivateKey(): PrivateKey? = try {
        keyStore().getKey(KEY_ALIAS, null) as? PrivateKey
    } catch (e: Exception) {
        null
    }

    private fun newSignature(): Signature {
        val key = loadPrivateKey() ?: throw IllegalStateException("NO_KEY")
        return Signature.getInstance("SHA256withECDSA").apply { initSign(key) }
    }

    private fun keyValid(): Boolean = try {
        newSignature()
        true
    } catch (e: KeyPermanentlyInvalidatedException) {
        false
    } catch (e: Exception) {
        false
    }

    // ───────────── key creation ─────────────
    @Suppress("DEPRECATION")
    private fun generate(strongBox: Boolean): String {
        val builder = KeyGenParameterSpec.Builder(KEY_ALIAS, KeyProperties.PURPOSE_SIGN)
            .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
            .setDigests(KeyProperties.DIGEST_SHA256)
            .setUserAuthenticationRequired(true)
            .setInvalidatedByBiometricEnrollment(true)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            // timeout 0 = authenticate for every single use, fingerprint class only
            builder.setUserAuthenticationParameters(0, KeyProperties.AUTH_BIOMETRIC_STRONG)
        } else {
            builder.setUserAuthenticationValidityDurationSeconds(-1) // every use
        }
        if (strongBox && Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            builder.setIsStrongBoxBacked(true)
        }

        val generator = KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_EC, ANDROID_KEYSTORE)
        generator.initialize(builder.build())
        val pair = generator.generateKeyPair()
        return Base64.encodeToString(pair.public.encoded, Base64.NO_WRAP) // X.509 SubjectPublicKeyInfo
    }

    private fun createKey(result: MethodChannel.Result) {
        try {
            deleteKey()
            val publicKey = try {
                generate(strongBox = true)
            } catch (e: Exception) {
                deleteKey()
                generate(strongBox = false) // phone without StrongBox
            }
            result.success(publicKey)
        } catch (e: Exception) {
            result.error("KEY_ERROR", e.message ?: "Could not create the key", null)
        }
    }

    private fun deleteKey() {
        try {
            val ks = keyStore()
            if (ks.containsAlias(KEY_ALIAS)) ks.deleteEntry(KEY_ALIAS)
        } catch (_: Exception) {
        }
    }

    // ───────────── signing behind the fingerprint prompt ─────────────
    private fun sign(payload: String?, title: String?, subtitle: String?, result: MethodChannel.Result) {
        if (payload.isNullOrEmpty()) {
            result.error("INVALID_PAYLOAD", "Nothing to sign", null)
            return
        }
        if (busy) {
            result.error("BUSY", "A fingerprint prompt is already open", null)
            return
        }

        val signature = try {
            newSignature()
        } catch (e: KeyPermanentlyInvalidatedException) {
            result.error("KEY_INVALIDATED", "Fingerprints changed", null)
            return
        } catch (e: IllegalStateException) {
            result.error("NO_KEY", "No key on this phone", null)
            return
        } catch (e: Exception) {
            result.error("KEY_ERROR", e.message ?: "Key error", null)
            return
        }

        busy = true
        val executor = ContextCompat.getMainExecutor(activity)
        val prompt = BiometricPrompt(activity, executor, object : BiometricPrompt.AuthenticationCallback() {
            override fun onAuthenticationSucceeded(r: BiometricPrompt.AuthenticationResult) {
                try {
                    val s = r.cryptoObject?.signature ?: throw IllegalStateException("No crypto object")
                    s.update(payload.toByteArray(Charsets.UTF_8))
                    val bytes = s.sign()
                    busy = false
                    result.success(Base64.encodeToString(bytes, Base64.NO_WRAP))
                } catch (e: Exception) {
                    busy = false
                    result.error("SIGN_FAILED", e.message ?: "Signing failed", null)
                }
            }

            override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                busy = false
                val code = when (errorCode) {
                    BiometricPrompt.ERROR_USER_CANCELED,
                    BiometricPrompt.ERROR_NEGATIVE_BUTTON,
                    BiometricPrompt.ERROR_CANCELED -> "CANCELLED"
                    BiometricPrompt.ERROR_LOCKOUT,
                    BiometricPrompt.ERROR_LOCKOUT_PERMANENT -> "LOCKED_OUT"
                    else -> "AUTH_ERROR"
                }
                result.error(code, errString.toString(), null)
            }
            // onAuthenticationFailed: wrong finger, the prompt stays open for another try
        })

        val info = BiometricPrompt.PromptInfo.Builder()
            .setTitle(title ?: "Confirm it's you")
            .setSubtitle(subtitle)
            .setAllowedAuthenticators(BIOMETRIC_STRONG) // fingerprint only: no PIN / pattern / password
            .setNegativeButtonText("Cancel")
            .setConfirmationRequired(false)
            .build()

        prompt.authenticate(info, BiometricPrompt.CryptoObject(signature))
    }
}