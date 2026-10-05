package __ANDROID_NAMESPACE__

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
            "net.zerexa.nekoloc/update_source").setMethodCallHandler { call, result ->
            when (call.method) {
                "installerPackage" -> {
                    try {
                        val installer = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                            packageManager.getInstallSourceInfo(packageName).installingPackageName
                        } else {
                            @Suppress("DEPRECATION")
                            packageManager.getInstallerPackageName(packageName)
                        }
                        result.success(installer)
                    } catch (error: Exception) {
                        result.error("INSTALL_SOURCE_UNAVAILABLE", error.javaClass.simpleName, null)
                    }
                }
                "openPlayStore" -> {
                    try {
                        startActivity(Intent(Intent.ACTION_VIEW,
                            Uri.parse("market://details?id=$packageName"))
                            .setPackage("com.android.vending"))
                        result.success(true)
                    } catch (error: ActivityNotFoundException) {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
