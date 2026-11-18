package dev.dualforum.forum_app

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageInstaller
import android.content.pm.PackageManager
import android.os.Build
import android.widget.Toast
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest

object UpdateInstaller {
    @Suppress("DEPRECATION")
    private fun signatures(info: PackageInfo): Set<String> {
        val signatures = if (Build.VERSION.SDK_INT >= 28) info.signingInfo?.apkContentsSigners else info.signatures
        return signatures?.map { it.toCharsString() }?.toSet() ?: emptySet()
    }

    fun install(context: Context, address: String, version: String, digest: String, size: Long): String {
        require(context.packageName == "dev.dualforum.forum_app.release") { "测试版不能覆盖安装正式版" }
        require(Regex("v[0-9]+\\.[0-9]+\\.[0-9]+").matches(version)) { "版本号无效" }
        require(Regex("[a-f0-9]{64}").matches(digest) && size in 1..209715200) { "更新包信息无效" }
        val url = URL(address)
        val expected = "/wshhfy/V2DO/releases/download/$version/V2DO-${version.substring(1)}-"
        require(url.protocol == "https" && url.host == "github.com" && url.port == -1 && url.path.startsWith(expected) &&
            Regex("(arm64-v8a|armeabi-v7a|x86_64|universal)\\.apk").matches(url.path.removePrefix(expected)) && url.query == null) { "更新地址无效" }
        if (Build.VERSION.SDK_INT >= 26 && !context.packageManager.canRequestPackageInstalls()) return "permission"
        val file = java.io.File(context.cacheDir, "v2do-update.apk")
        try {
            var current = url
            var response: HttpURLConnection? = null
            for (i in 0..5) {
                val conn = current.openConnection() as HttpURLConnection
                conn.instanceFollowRedirects = false
                conn.connectTimeout = 20000
                conn.readTimeout = 45000
                conn.setRequestProperty("User-Agent", "V2DO updater")
                val code = conn.responseCode
                if (code in 300..399) {
                    val next = URL(current, conn.getHeaderField("Location") ?: throw IllegalStateException("下载重定向无效"))
                    conn.disconnect()
                    require(next.protocol == "https" && next.port in listOf(-1, 443) && next.host in listOf("github.com", "release-assets.githubusercontent.com", "objects.githubusercontent.com")) { "下载地址不安全" }
                    current = next
                } else {
                    if (code != 200) { conn.disconnect(); throw IllegalStateException("下载失败（$code）") }
                    response = conn
                    break
                }
            }
            val conn = response ?: throw IllegalStateException("下载重定向次数过多")
            val hash = MessageDigest.getInstance("SHA-256")
            var count = 0L
            try {
                conn.inputStream.use { input -> file.outputStream().use { out ->
                    val buffer = ByteArray(65536)
                    while (true) {
                        val n = input.read(buffer)
                        if (n < 0) break
                        count += n
                        require(count <= size) { "更新包大小不匹配" }
                        hash.update(buffer, 0, n)
                        out.write(buffer, 0, n)
                    }
                } }
            } finally { conn.disconnect() }
            val actual = hash.digest().joinToString("") { "%02x".format(it.toInt() and 255) }
            require(count == size && actual == digest) { "更新包完整性校验失败" }
            val pm = context.packageManager
            @Suppress("DEPRECATION") val flags = if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES else PackageManager.GET_SIGNATURES
            @Suppress("DEPRECATION") val archive = pm.getPackageArchiveInfo(file.absolutePath, flags) ?: throw IllegalStateException("无法读取更新包")
            @Suppress("DEPRECATION") val installed = pm.getPackageInfo(context.packageName, flags)
            @Suppress("DEPRECATION") val oldCode = if (Build.VERSION.SDK_INT >= 28) installed.longVersionCode else installed.versionCode.toLong()
            @Suppress("DEPRECATION") val newCode = if (Build.VERSION.SDK_INT >= 28) archive.longVersionCode else archive.versionCode.toLong()
            require(archive.packageName == context.packageName && archive.versionName == version.substring(1) && newCode > oldCode && signatures(installed).isNotEmpty() && signatures(installed) == signatures(archive)) { "更新包的应用、版本或签名不匹配" }
            val installer = pm.packageInstaller
            val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL)
            params.setAppPackageName(context.packageName)
            if (Build.VERSION.SDK_INT >= 31) params.setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_NOT_REQUIRED)
            val sessionId = installer.createSession(params)
            val session = installer.openSession(sessionId)
            try {
                session.openWrite("base.apk", 0, size).use { output -> file.inputStream().use { it.copyTo(output) }; session.fsync(output) }
                val intent = Intent(context, UpdateInstallReceiver::class.java)
                val flagsPending = PendingIntent.FLAG_UPDATE_CURRENT or if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0
                val pending = PendingIntent.getBroadcast(context, sessionId, intent, flagsPending)
                session.commit(pending.intentSender)
            } catch (e: Exception) { session.abandon(); throw e } finally { session.close() }
            return "started"
        } finally { file.delete() }
    }
}

class UpdateInstallReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)) {
            PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                @Suppress("DEPRECATION") val confirmation = if (Build.VERSION.SDK_INT >= 33) intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java) else intent.getParcelableExtra(Intent.EXTRA_INTENT)
                if (confirmation != null) {
                    confirmation.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    try { context.startActivity(confirmation) } catch (_: Exception) { Toast.makeText(context, "请打开应用完成更新安装", Toast.LENGTH_LONG).show() }
                }
            }
            PackageInstaller.STATUS_SUCCESS -> Toast.makeText(context, "V2DO 更新完成", Toast.LENGTH_SHORT).show()
            else -> Toast.makeText(context, "更新安装失败，请在设置中重试", Toast.LENGTH_LONG).show()
        }
    }
}
