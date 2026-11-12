package com.horeeye.xaadir // <- must match your applicationId

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterFragmentActivity() {
    // Keep a reference so the channel isn't garbage collected
    private var biometric: BiometricChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        biometric = BiometricChannel(this, flutterEngine.dartExecutor.binaryMessenger)
    }
}