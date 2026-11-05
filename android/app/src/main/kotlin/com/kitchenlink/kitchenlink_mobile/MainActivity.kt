package com.kitchenlink.kitchenlink_mobile

import android.content.ActivityNotFoundException
import android.content.Intent
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Opens a downloaded file (e.g. a vendor's PDF document) in a viewer app.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kitchenlink/files").setMethodCallHandler { call, result ->
            if (call.method != "open") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val path = call.argument<String>("path")
            val mime = call.argument<String>("mime") ?: "*/*"
            if (path == null) {
                result.error("NO_PATH", "No file to open.", null)
                return@setMethodCallHandler
            }
            try {
                val uri = FileProvider.getUriForFile(this, "$packageName.files", File(path))
                val intent = Intent(Intent.ACTION_VIEW)
                    .setDataAndType(uri, mime)
                    .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                startActivity(Intent.createChooser(intent, null))
                result.success(true)
            } catch (error: ActivityNotFoundException) {
                result.error("NO_APP", "No app on this phone can open this file.", null)
            } catch (error: Exception) {
                result.error("OPEN_FAILED", error.message ?: "Could not open the file.", null)
            }
        }
    }
}
