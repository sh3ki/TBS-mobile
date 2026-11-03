package com.tbs.mobile.tbs_mobile

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val channelName = "com.tbs.mobile.tbs_mobile/apk_installer"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                if (call.method == "getAppVersion") {
                    try {
                        val packageInfo = packageManager.getPackageInfo(packageName, 0)
                        result.success(packageInfo.versionName ?: "")
                    } catch (error: Exception) {
                        result.error("APP_VERSION_UNAVAILABLE", error.message, null)
                    }
                    return@setMethodCallHandler
                }

                if (call.method != "installApk") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }

                val path = call.argument<String>("path")
                if (path.isNullOrBlank()) {
                    result.error("INVALID_APK_PATH", "APK path is missing.", null)
                    return@setMethodCallHandler
                }

                try {
                    val apkFile = File(path)
                    if (!apkFile.exists()) {
                        result.error("APK_NOT_FOUND", "Downloaded APK was not found.", null)
                        return@setMethodCallHandler
                    }

                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                        !packageManager.canRequestPackageInstalls()
                    ) {
                        startActivity(
                            Intent(
                                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                Uri.parse("package:$packageName"),
                            ),
                        )
                        result.error(
                            "UNKNOWN_SOURCES_PERMISSION_REQUIRED",
                            "Allow this app to install unknown apps, then try again.",
                            null,
                        )
                        return@setMethodCallHandler
                    }

                    val apkUri: Uri = FileProvider.getUriForFile(
                        this,
                        "${applicationContext.packageName}.fileprovider",
                        apkFile,
                    )
                    val installIntent = Intent(Intent.ACTION_VIEW).apply {
                        setDataAndType(apkUri, "application/vnd.android.package-archive")
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    startActivity(installIntent)
                    result.success(true)
                } catch (error: Exception) {
                    result.error("INSTALL_APK_FAILED", error.message, null)
                }
            }
    }
}
