package com.example.wft

import android.nfc.NfcAdapter
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pending: MethodChannel.Result? = null
    private val handler = Handler(Looper.getMainLooper())
    private val timeout = Runnable { finishScan(null, "No se detectó una tarjeta. Inténtalo de nuevo.") }
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ec.frederick.escolar/nfc").setMethodCallHandler { call, result ->
            when (call.method) {
                "cancel" -> { finishScan(null, "Lectura cancelada."); result.success(null) }
                "scan" -> {
                    val adapter = NfcAdapter.getDefaultAdapter(this)
                    if (adapter == null || !adapter.isEnabled) {
                        result.error("unavailable", "Este teléfono no tiene NFC o está desactivado. Puedes escribir el código de la tarjeta en la web.", null)
                    } else if (pending != null) {
                        result.error("busy", "Ya hay una lectura en curso.", null)
                    } else {
                        pending = result
                        try {
                            adapter.enableReaderMode(this, { tag ->
                                val uid = tag.id.joinToString(":") { "%02X".format(it.toInt() and 0xff) }
                                runOnUiThread { finishScan(uid, null) }
                            }, NfcAdapter.FLAG_READER_NFC_A or NfcAdapter.FLAG_READER_NFC_B or NfcAdapter.FLAG_READER_NFC_F or NfcAdapter.FLAG_READER_NFC_V or NfcAdapter.FLAG_READER_SKIP_NDEF_CHECK, Bundle())
                            handler.postDelayed(timeout, 30000)
                        } catch (_: Exception) { finishScan(null, "No se pudo iniciar el lector NFC.") }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
    private fun finishScan(uid: String?, error: String?) {
        handler.removeCallbacks(timeout)
        try { NfcAdapter.getDefaultAdapter(this)?.disableReaderMode(this) } catch (_: Exception) {}
        val result = pending
        pending = null
        if (error == null) result?.success(uid) else result?.error("scan_failed", error, null)
    }
    override fun onPause() { finishScan(null, "Lectura interrumpida. Vuelve a intentarlo."); super.onPause() }
}
