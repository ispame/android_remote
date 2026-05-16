package com.openclaw.remote.headset

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.util.concurrent.TimeUnit

data class MiniMaxVoiceOption(
    val id: String,
    val name: String,
    val category: String,
)

object MiniMaxVoiceCatalog {
    const val DEFAULT_VOICE_ID: String = "male-qn-qingse"

    val builtinVoices: List<MiniMaxVoiceOption> = listOf(
        MiniMaxVoiceOption("male-qn-qingse", "青涩青年音色", "中文"),
        MiniMaxVoiceOption("female-shaonv", "少女音色", "中文"),
        MiniMaxVoiceOption("female-yujie", "御姐音色", "中文"),
        MiniMaxVoiceOption("female-chengshu", "成熟女性音色", "中文"),
        MiniMaxVoiceOption("female-tianmei", "甜美女性音色", "中文"),
        MiniMaxVoiceOption("danya_xuejie", "淡雅学姐", "中文"),
        MiniMaxVoiceOption("Chinese (Mandarin)_Reliable_Executive", "沉稳高管", "中文"),
        MiniMaxVoiceOption("Chinese (Mandarin)_News_Anchor", "新闻女声", "中文"),
        MiniMaxVoiceOption("Chinese (Mandarin)_Mature_Woman", "傲娇御姐", "中文"),
        MiniMaxVoiceOption("Chinese (Mandarin)_HK_Flight_Attendant", "港普空姐", "中文"),
        MiniMaxVoiceOption("Chinese (Mandarin)_Gentleman", "温润男声", "中文"),
        MiniMaxVoiceOption("Chinese (Mandarin)_Warm_Girl", "温暖少女", "中文"),
        MiniMaxVoiceOption("Chinese (Mandarin)_Lyrical_Voice", "抒情男声", "中文"),
        MiniMaxVoiceOption("Cantonese_ProfessionalHost（F)", "专业女主持", "粤语"),
        MiniMaxVoiceOption("Cantonese_GentleLady", "温柔女声", "粤语"),
        MiniMaxVoiceOption("Cantonese_ProfessionalHost（M)", "专业男主持", "粤语"),
        MiniMaxVoiceOption("Cantonese_PlayfulMan", "活泼男声", "粤语"),
        MiniMaxVoiceOption("Cantonese_CuteGirl", "可爱女孩", "粤语"),
        MiniMaxVoiceOption("Cantonese_KindWoman", "善良女声", "粤语"),
        MiniMaxVoiceOption("Charming_Lady", "Charming Lady", "英文"),
        MiniMaxVoiceOption("Sweet_Girl", "Sweet Girl", "英文"),
        MiniMaxVoiceOption("Arnold", "Arnold", "英文"),
        MiniMaxVoiceOption("Japanese_IntellectualSenior", "Intellectual Senior", "日文"),
        MiniMaxVoiceOption("Japanese_DecisivePrincess", "Decisive Princess", "日文"),
        MiniMaxVoiceOption("Japanese_LoyalKnight", "Loyal Knight", "日文"),
        MiniMaxVoiceOption("Japanese_ColdQueen", "Cold Queen", "日文"),
    ).distinctBy { it.id }

    fun buildSelectableVoices(
        currentVoiceId: String,
        fetchedVoices: List<MiniMaxVoiceOption>,
    ): List<MiniMaxVoiceOption> {
        val baseVoices = fetchedVoices.ifEmpty { builtinVoices }
        val current = currentVoiceId.takeIf { it.isNotBlank() && baseVoices.none { voice -> voice.id == it } }?.let {
            MiniMaxVoiceOption(it, it, "当前配置")
        }

        return (listOfNotNull(current) + baseVoices)
            .distinctBy { it.id }
            .distinctBy { it.displayKey() }
    }

    suspend fun fetchAvailableVoices(apiKey: String): List<MiniMaxVoiceOption> = withContext(Dispatchers.IO) {
        if (apiKey.isBlank()) return@withContext emptyList()

        val client = OkHttpClient.Builder()
            .connectTimeout(15, TimeUnit.SECONDS)
            .readTimeout(30, TimeUnit.SECONDS)
            .writeTimeout(15, TimeUnit.SECONDS)
            .build()
        val requestBody = JSONObject()
            .put("voice_type", "all")
            .toString()
            .toRequestBody("application/json".toMediaType())
        val request = Request.Builder()
            .url("https://api.minimaxi.com/v1/get_voice")
            .addHeader("Authorization", "Bearer $apiKey")
            .addHeader("Content-Type", "application/json")
            .post(requestBody)
            .build()

        client.newCall(request).execute().use { response ->
            val body = response.body?.string().orEmpty()
            if (!response.isSuccessful) {
                throw IllegalStateException("MiniMax voice list error: ${response.code}, body: $body")
            }
            parseGetVoiceResponse(body)
        }
    }

    fun parseGetVoiceResponse(responseBody: String): List<MiniMaxVoiceOption> {
        val root = JSONObject(responseBody)
        val baseResp = root.optJSONObject("base_resp")
        val statusCode = baseResp?.optInt("status_code", 0) ?: 0
        val statusMsg = baseResp?.optString("status_msg", "") ?: ""
        if (statusCode != 0) {
            throw IllegalStateException("MiniMax voice list provider error status_code=$statusCode status_msg=$statusMsg")
        }

        return listOf(
            "system_voice" to "系统音色",
            "voice_cloning" to "复刻音色",
            "voice_generation" to "文生音色",
        ).flatMap { (field, category) ->
            val array = root.optJSONArray(field) ?: return@flatMap emptyList()
            buildList {
                for (index in 0 until array.length()) {
                    val item = array.optJSONObject(index) ?: continue
                    val id = item.optString("voice_id").ifBlank { item.optString("id") }.trim()
                    if (id.isBlank()) continue
                    val name = item.optString("voice_name")
                        .ifBlank { item.optString("name") }
                        .ifBlank { id }
                    add(MiniMaxVoiceOption(id = id, name = name, category = category))
                }
            }
        }.distinctBy { it.id }
    }

    private fun MiniMaxVoiceOption.displayKey(): String =
        "${category.trim()}|${name.trim()}".lowercase()
}
