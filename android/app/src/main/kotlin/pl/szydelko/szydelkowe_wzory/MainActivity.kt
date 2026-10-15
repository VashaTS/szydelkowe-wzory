package pl.szydelko.szydelkowe_wzory

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "szydelko/files"
    private var channel: MethodChannel? = null
    private var pending: Map<String, Any?>? = null
    private var pickResult: MethodChannel.Result? = null
    private val pickCode = 4711

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pending = readIntent(intent)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialFile" -> { result.success(pending); pending = null }
                    "pickFile" -> {
                        pickResult = result
                        val i = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "*/*"
                        }
                        try { startActivityForResult(i, pickCode) } catch (e: Exception) {
                            pickResult = null; result.error("nopicker", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        readIntent(intent)?.let { channel?.invokeMethod("fileOpened", it) }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != pickCode) return
        val r = pickResult ?: return
        pickResult = null
        val uri = data?.data
        if (resultCode != RESULT_OK || uri == null) { r.success(null); return }
        try { r.success(readUri(uri)) } catch (e: Exception) { r.error("read", e.message, null) }
    }

    private fun readIntent(i: Intent?): Map<String, Any?>? {
        if (i == null) return null
        val uri: Uri? = when (i.action) {
            Intent.ACTION_VIEW -> i.data
            Intent.ACTION_SEND ->
                if (Build.VERSION.SDK_INT >= 33) i.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
                else @Suppress("DEPRECATION") (i.getParcelableExtra(Intent.EXTRA_STREAM) as? Uri)
            else -> null
        } ?: return null
        if (uri == null) return null
        return try { readUri(uri) } catch (e: Exception) { mapOf("error" to (e.message ?: "read error")) }
    }

    private fun readUri(uri: Uri): Map<String, Any?> {
        var name: String? = null
        try {
            contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
                if (it.moveToFirst()) name = it.getString(0)
            }
        } catch (_: Exception) {}
        if (name == null) name = uri.lastPathSegment
        val bytes = contentResolver.openInputStream(uri)?.use { s ->
            val out = java.io.ByteArrayOutputStream()
            val buf = ByteArray(65536); var total = 0
            while (true) {
                val n = s.read(buf); if (n < 0) break
                total += n; if (total > 30 * 1024 * 1024) throw Exception("Plik za duży")
                out.write(buf, 0, n)
            }
            out.toByteArray()
        } ?: throw Exception("Nie można otworzyć pliku")
        return mapOf("name" to name, "text" to String(bytes, Charsets.UTF_8))
    }
}
