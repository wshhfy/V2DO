package dev.dualforum.forum_app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.webkit.CookieManager
import android.webkit.WebSettings
import java.net.HttpURLConnection
import java.net.URI
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private var saveResult: MethodChannel.Result? = null
    private var saveBytes: ByteArray? = null
    private fun saveImage(bytes: ByteArray?, result: MethodChannel.Result) {
        if (bytes == null || bytes.isEmpty() || bytes.size > 64 * 1024 * 1024) {
            result.error("SAVE_IMAGE", "图片无效或超过 64 MB", null); return
        }
        if (saveResult != null) { result.error("BUSY", "正在保存图片", null); return }
        saveResult = result
        executor.execute {
            try {
                val options = android.graphics.BitmapFactory.Options().apply { inJustDecodeBounds = true }
                android.graphics.BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options)
                val mime = options.outMimeType ?: throw IllegalArgumentException("无法识别图片格式")
                val suffix = android.webkit.MimeTypeMap.getSingleton().getExtensionFromMimeType(mime) ?: "img"
                val name = "V2DO_${System.currentTimeMillis()}.$suffix"
                if (android.os.Build.VERSION.SDK_INT >= 29) {
                    val values = android.content.ContentValues().apply {
                        put(android.provider.MediaStore.Images.Media.DISPLAY_NAME, name)
                        put(android.provider.MediaStore.Images.Media.MIME_TYPE, mime)
                        put(android.provider.MediaStore.Images.Media.RELATIVE_PATH, "Pictures/V2DO")
                        put(android.provider.MediaStore.Images.Media.IS_PENDING, 1)
                    }
                    val uri = contentResolver.insert(android.provider.MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
                        ?: throw IllegalStateException("无法创建图片")
                    try {
                        (contentResolver.openOutputStream(uri) ?: throw IllegalStateException("无法写入图片")).use { it.write(bytes) }
                        values.clear()
                        values.put(android.provider.MediaStore.Images.Media.IS_PENDING, 0)
                        contentResolver.update(uri, values, null, null)
                    } catch (e: Exception) { contentResolver.delete(uri, null, null); throw e }
                    runOnUiThread { saveResult = null; result.success("相册 V2DO") }
                } else runOnUiThread {
                    saveBytes = bytes
                    try {
                        startActivityForResult(android.content.Intent(android.content.Intent.ACTION_CREATE_DOCUMENT).apply {
                            addCategory(android.content.Intent.CATEGORY_OPENABLE)
                            type = mime
                            putExtra(android.content.Intent.EXTRA_TITLE, name)
                        }, 3108)
                    } catch (e: Exception) { saveBytes = null; saveResult = null; result.error("SAVE_IMAGE", e.message, null) }
                }
            } catch (e: Exception) { runOnUiThread { saveResult = null; result.error("SAVE_IMAGE", e.message, null) } }
        }
    }
    private var recoveryView: android.webkit.WebView? = null
    private fun refreshLinuxSession(result: MethodChannel.Result) {
        if (recoveryView != null) {
            result.success(false); return
        }
        val view = android.webkit.WebView(this)
        recoveryView = view
        val handler = android.os.Handler(android.os.Looper.getMainLooper())
        var finished = false
        fun finish(ok: Boolean) {
            if (finished) return
            finished = true
            handler.removeCallbacksAndMessages(null)
            recoveryView = null
            view.stopLoading()
            view.destroy()
            executor.execute {
                val flushed = try { CookieManager.getInstance().flush(); true } catch (_: Exception) { false }
                runOnUiThread { result.success(ok && flushed) }
            }
        }
        view.settings.javaScriptEnabled = true
        view.settings.domStorageEnabled = true
        view.webViewClient = object : android.webkit.WebViewClient() {
            override fun shouldOverrideUrlLoading(v: android.webkit.WebView, r: android.webkit.WebResourceRequest): Boolean = r.url.scheme != "https" || r.url.host != "linux.do"
            override fun onPageFinished(v: android.webkit.WebView, url: String) {
                if (!url.startsWith("https://linux.do/")) return
                fun checkAccount() {
                    if (finished) return
                    v.evaluateJavascript("""(()=>{if(window.__v2doChecking)return !!window.__v2doLoggedIn;window.__v2doChecking=true;fetch('/session/current.json',{credentials:'same-origin',headers:{'Accept':'application/json'}}).then(r=>r.ok?r.json():null).then(j=>{window.__v2doLoggedIn=!!(j&&j.current_user&&j.current_user.username)}).catch(()=>{}).finally(()=>{window.__v2doChecking=false});return !!window.__v2doLoggedIn})()""") { answer ->
                        if (finished) return@evaluateJavascript
                        if (answer == "true") finish(true)
                        else handler.postDelayed({ checkAccount() }, 1500)
                    }
                }
                handler.postDelayed({ checkAccount() }, 800)
            }
            override fun onReceivedError(v: android.webkit.WebView, r: android.webkit.WebResourceRequest, e: android.webkit.WebResourceError) {
                if (r.isForMainFrame) finish(false)
            }
        }
        handler.postDelayed({ finish(false) }, 18000)
        view.loadUrl("https://linux.do/login")
    }
    private var pickerResult: MethodChannel.Result? = null
    private val executor = Executors.newFixedThreadPool(3)
    private val imageExecutor = Executors.newFixedThreadPool(3)
    private lateinit var userAgent: String
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        userAgent = WebSettings.getDefaultUserAgent(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dualforum/session").setMethodCallHandler { call, result ->
            if (call.method == "updateDevice") {
                result.success(mapOf("abis" to android.os.Build.SUPPORTED_ABIS.toList(), "supported" to (packageName == "dev.dualforum.forum_app.release")))
                return@setMethodCallHandler
            }
            if (call.method == "installUpdate") {
                val url = call.argument<String>("url") ?: ""
                val version = call.argument<String>("version") ?: ""
                val digest = call.argument<String>("digest") ?: ""
                val size = call.argument<Number>("size")?.toLong() ?: 0L
                executor.execute {
                    try {
                        val status = UpdateInstaller.install(this, url, version, digest, size)
                        runOnUiThread { result.success(status) }
                    } catch (e: Exception) {
                        runOnUiThread { result.error("UPDATE", e.message ?: "更新失败，请稍后重试", null) }
                    }
                }
                return@setMethodCallHandler
            }
            if (call.method == "updateInstallPermission") {
                val intent = android.content.Intent(android.provider.Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, android.net.Uri.parse("package:$packageName"))
                startActivity(intent)
                result.success(null)
                return@setMethodCallHandler
            }
            if (call.method == "resetApplication") {
                try {
                    val manager = getSystemService(android.content.Context.ACTIVITY_SERVICE) as android.app.ActivityManager
                    if (!manager.clearApplicationUserData()) result.error("RESET", "系统未能重置应用，请重试", null)
                } catch (_: Exception) { result.error("RESET", "重置失败，请重试", null) }
                return@setMethodCallHandler
            }
            if (call.method == "saveImage") { saveImage(call.argument<ByteArray>("bytes"), result); return@setMethodCallHandler }
            if (call.method == "clearImgurSession") {
                try {
                    val manager = CookieManager.getInstance()
                    val hosts = listOf("imgur.com", "www.imgur.com", "api.imgur.com")
                    val operations = mutableListOf<Pair<String, String>>()
                    for (host in hosts) {
                        val url = "https://$host/"
                        val names = (manager.getCookie(url) ?: "").split(';').mapNotNull {
                            val name = it.trim().substringBefore('=')
                            name.takeIf { n -> n.isNotEmpty() }
                        }.distinct()
                        for (name in names) {
                            operations.add(url to "$name=; Max-Age=0; Path=/; Secure")
                            operations.add(url to "$name=; Max-Age=0; Path=/; Domain=.imgur.com; Secure")
                        }
                    }
                    if (operations.isEmpty()) { result.success(null); return@setMethodCallHandler }
                    var pending = operations.size
                    for ((url, cookie) in operations) manager.setCookie(url, cookie) {
                        pending--
                        if (pending == 0) { manager.flush(); result.success(null) }
                    }
                } catch (e: Exception) { result.error("IMGUR_LOGOUT", "清除 Imgur 登录状态失败", null) }
                return@setMethodCallHandler
            }
            if (call.method == "refreshLinuxSession") { refreshLinuxSession(result); return@setMethodCallHandler }
            if (call.method == "pickImage") {
                if (pickerResult != null) { result.error("BUSY", "图片选择器已经打开", null); return@setMethodCallHandler }
                pickerResult = result
                try {
                    startActivityForResult(android.content.Intent(android.content.Intent.ACTION_OPEN_DOCUMENT).apply {
                        type = "image/*"
                        addCategory(android.content.Intent.CATEGORY_OPENABLE)
                    }, 3107)
                } catch (_: Exception) { pickerResult = null; result.error("PICKER", "无法打开系统图片选择器", null) }
                return@setMethodCallHandler
            }
            if (call.method == "getPreferences") {
                result.success(getSharedPreferences("exdo_settings", MODE_PRIVATE).all)
                return@setMethodCallHandler
            }
            if (call.method == "setPreferences") {
                val values = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
                val edit = getSharedPreferences("exdo_settings", MODE_PRIVATE).edit()
                for ((key, value) in values) when (key) {
                    "theme" -> if (value is String && value in setOf("system", "light", "dark")) edit.putString("theme", value)
                    "accent" -> if (value is Number) edit.putInt("accent", value.toInt())
                    "autoUpdate" -> if (value is Boolean) edit.putBoolean("autoUpdate", value)
                    "imgurClientId" -> if (value is String && (value.isEmpty() || value.matches(Regex("[a-zA-Z0-9]{8,64}")))) edit.putString("imgurClientId", value)
                    "lastUpdateCheck" -> if (value is Number) edit.putLong("lastUpdateCheck", value.toLong())
                    "v2exKnownBlocks" -> if (value is String && value.length <= 262144) edit.putString("v2exKnownBlocks", value)
                    "recentVisits" -> if (value is String && value.length <= 524288) edit.putString("recentVisits", value)
                    "knownAccounts" -> if (value is String && value.length <= 16384) edit.putString("knownAccounts", value)
                    "startForum" -> if (value is Number && value.toInt() in 0..1) edit.putInt("startForum", value.toInt())
                }
                edit.apply()
                result.success(null)
                return@setMethodCallHandler
            }
            if (call.method != "request") { result.notImplemented(); return@setMethodCallHandler }
            val address = call.argument<String>("url") ?: ""
            val uri = try { URI(address) } catch (_: Exception) { null }
            val method = call.argument<String>("method") ?: "GET"
            val imgurRequest = uri?.host == "api.imgur.com" && ((method == "GET" && uri.path == "/3/account/me") || (method == "POST" && uri.path == "/3/upload"))
            if (uri == null || uri.scheme != "https" || (uri.host !in setOf("www.v2ex.com", "linux.do") && !imgurRequest) || uri.port !in setOf(-1, 443) || method !in setOf("GET", "POST", "PUT", "DELETE") || (method == "DELETE" && (uri.host != "linux.do" || !(uri.path.startsWith("/session/") || uri.path.matches(Regex("/(bookmarks|post_actions)/[0-9]+\\.json"))))) || (method == "PUT" && (uri.host != "linux.do" || uri.path != "/notifications/mark-read.json"))) {
                result.error("INVALID_REQUEST", "Unsupported forum request", null); return@setMethodCallHandler
            }
            val cookies = CookieManager.getInstance().getCookie(address)
            val body = call.argument<String>("body")
            val requestBytes = call.argument<ByteArray>("bodyBytes")
            if (requestBytes != null && (method != "POST" || !((uri.host == "linux.do" && uri.path == "/uploads.json") || (imgurRequest && uri.path == "/3/upload")) || requestBytes.size > 26 * 1024 * 1024)) {
                result.error("INVALID_UPLOAD", "图片上传请求无效或超过 25 MB", null); return@setMethodCallHandler
            }
            val binary = call.argument<Boolean>("binary") == true && method == "GET"
            val extraHeaders = call.argument<Map<String, String>>("headers") ?: emptyMap()
            (if (binary) imageExecutor else executor).execute {
                var connection: HttpURLConnection? = null
                try {
                    connection = uri.toURL().openConnection() as HttpURLConnection
                    connection.instanceFollowRedirects = false
                    connection.requestMethod = method
                    connection.connectTimeout = 20000
                    connection.readTimeout = if (requestBytes != null) 120000 else 30000
                    connection.setRequestProperty("User-Agent", userAgent)
                    if (!cookies.isNullOrEmpty()) connection.setRequestProperty("Cookie", cookies)
                    for ((key, value) in extraHeaders) {
                        if (key.lowercase() in setOf("accept", "content-type", "x-csrf-token", "x-requested-with", "referer", "origin", "user-agent")) connection.setRequestProperty(key, value)
                    }
                    if (method == "POST" || method == "PUT") {
                        connection.doOutput = true
                        val payload = requestBytes ?: (body ?: "").toByteArray(Charsets.UTF_8)
                        connection.setFixedLengthStreamingMode(payload.size)
                        connection.outputStream.use { it.write(payload) }
                    }
                    val status = connection.responseCode
                    val stream = if (status >= 400) connection.errorStream else connection.inputStream
                    val bytes = if (binary) stream?.use { it.readBytes() } else null
                    val content = if (binary) "" else stream?.bufferedReader(Charsets.UTF_8)?.use { it.readText() } ?: ""
                    val location = connection.getHeaderField("Location") ?: ""
                    val setCookies = connection.headerFields.entries.filter { it.key?.equals("Set-Cookie", true) == true }.flatMap { it.value }
                    runOnUiThread {
                        val manager = CookieManager.getInstance()
                        if (setCookies.isNotEmpty()) {
                            val pending = java.util.concurrent.atomic.AtomicInteger(setCookies.size)
                            for (cookie in setCookies) manager.setCookie(address, cookie) {
                                if (pending.decrementAndGet() == 0) {
                                    executor.execute { manager.flush() }
                                    result.success(mapOf("status" to status, "body" to content, "bytes" to bytes, "location" to location))
                                }
                            }
                        } else result.success(mapOf("status" to status, "body" to content, "bytes" to bytes, "location" to location))
                    }
                } catch (_: Exception) {
                    runOnUiThread { result.error("NETWORK", if (method == "POST") "发送结果未确认，请先刷新帖子核对，避免重复发送" else "网络请求失败，请重试", null) }
                } finally { connection?.disconnect() }
            }
        }
    }
    @Deprecated("Activity result API retained for FlutterActivity compatibility")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: android.content.Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == 3108) {
            val result = saveResult ?: return
            val bytes = saveBytes
            saveResult = null; saveBytes = null
            val uri = data?.data
            if (resultCode != RESULT_OK || uri == null || bytes == null) { result.success(null); return }
            executor.execute {
                try {
                    (contentResolver.openOutputStream(uri) ?: throw IllegalStateException("无法写入图片")).use { it.write(bytes) }
                    runOnUiThread { result.success("所选位置") }
                } catch (e: Exception) { runOnUiThread { result.error("SAVE_IMAGE", e.message, null) } }
            }
            return
        }
        if (requestCode != 3107) return
        val result = pickerResult ?: return
        pickerResult = null
        val uri = data?.data
        if (resultCode != RESULT_OK || uri == null) { result.success(null); return }
        executor.execute {
            try {
                val mime = contentResolver.getType(uri) ?: "application/octet-stream"
                if (!mime.startsWith("image/")) throw IllegalArgumentException("请选择图片文件")
                val bytes = contentResolver.openInputStream(uri)?.use { input ->
                    val out = java.io.ByteArrayOutputStream()
                    val buffer = ByteArray(8192)
                    while (true) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        if (out.size() + count > 25 * 1024 * 1024) throw IllegalArgumentException("V2DO 单张图片最大 25 MB，论坛还可能有更小的限制")
                        out.write(buffer, 0, count)
                    }
                    out.toByteArray()
                } ?: throw IllegalArgumentException("无法读取所选图片")
                val suffix = android.webkit.MimeTypeMap.getSingleton().getExtensionFromMimeType(mime) ?: "jpg"
                runOnUiThread { result.success(mapOf("bytes" to bytes, "mime" to mime, "name" to "image.$suffix")) }
            } catch (e: Exception) { runOnUiThread { result.error("IMAGE", e.message ?: "读取图片失败", null) } }
        }
    }
}

