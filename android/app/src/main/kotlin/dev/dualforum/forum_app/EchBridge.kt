package dev.dualforum.forum_app

import android.util.Base64
import org.json.JSONObject

object EchBridge {
    init { System.loadLibrary("v2do_ech") }
    @JvmStatic external fun request(input: String): String?

    fun call(url: String, method: String, headers: Map<String, String>, body: ByteArray): JSONObject {
        val input = JSONObject().put("url", url).put("method", method)
            .put("headers", JSONObject(headers)).put("body", Base64.encodeToString(body, Base64.NO_WRAP))
        val output = request(input.toString()) ?: throw IllegalStateException("ECH 引擎没有返回结果")
        val json = JSONObject(output)
        if (json.optString("error").isNotBlank()) throw IllegalStateException(json.optString("error"))
        return json
    }
}
