package com.openclaw.remote.auth

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.jsonObject
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class GatewayAuthClientTest {
    @Test
    fun convertsSecureGatewayWebSocketUrlToHttpsBase() {
        assertEquals(
            "https://boson-tech.top",
            authBaseUrlFromGatewayUrl("wss://boson-tech.top/ws"),
        )
    }

    @Test
    fun convertsLocalWebSocketUrlToHttpBase() {
        assertEquals(
            "http://192.168.1.14:8765",
            authBaseUrlFromGatewayUrl("ws://192.168.1.14:8765/ws"),
        )
    }

    @Test
    fun preservesExistingHttpSchemeAndStripsTrailingWsSegment() {
        assertEquals(
            "https://gateway.example.com/router",
            authBaseUrlFromGatewayUrl("https://gateway.example.com/router/ws"),
        )
    }

    @Test
    fun rejectsBlankOrUnsupportedGatewayUrl() {
        assertNull(authBaseUrlFromGatewayUrl(" "))
        assertNull(authBaseUrlFromGatewayUrl("gateway.example.com/ws"))
    }

    @Test
    fun parsesAccountDisplayNameWithMaskedPhoneFallback() {
        val json = Json.parseToJsonElement(
            """
            {
              "account_id": "acct_1",
              "display_name": null,
              "account_display_name": "138****8066",
              "phone_number_masked": "138****8066",
              "active_terminal": {"terminal_label": "Pixel", "connected_at": "2026-06-05T00:00:00.000Z"},
              "paired_backends_count": 2
            }
            """.trimIndent()
        ).jsonObject

        val me = parseAuthMe(json)

        assertEquals("acct_1", me.accountId)
        assertNull(me.displayName)
        assertEquals("138****8066", me.accountDisplayName)
        assertEquals("138****8066", me.phoneNumberMasked)
        assertEquals("Pixel", me.activeTerminalLabel)
        assertEquals(2, me.pairedBackendsCount)
    }

    @Test
    fun parsesBillingSummaryWithDynamicPlanProductsAndOrders() {
        val json = Json.parseToJsonElement(
            """
            {
              "account_id": "acct_1",
              "wallet": {"balance_cents": 0, "currency": "CNY"},
              "current_subscription": {
                "subscription_id": "sub_1",
                "product_id": "plan_starter_monthly",
                "status": "active",
                "current_period_end": "2026-07-01T00:00:00.000Z"
              },
              "products": {
                "plans": [{
                  "product_id": "plan_starter_monthly",
                  "kind": "plan",
                  "title": "Starter 月套餐",
                  "subtitle": "个人套餐",
                  "display_name": "Starter Monthly",
                  "amount_cents": 1900,
                  "currency": "CNY",
                  "billing_period": "month",
                  "benefits": ["基础消息权益"],
                  "badge": "推荐",
                  "sort_order": 10,
                  "available_providers": ["manual_qr"]
                }],
                "wallet_products": []
              },
              "recent_orders": [{
                "order_id": "ord_1",
                "product_id": "plan_starter_monthly",
                "product_kind": "plan",
                "provider": "manual_qr",
                "status": "pending",
                "amount_cents": 1900,
                "currency": "CNY",
                "expires_at": "2026-06-01T00:15:00.000Z",
                "payment_url": "https://pay.example.com/o/ord_1",
                "copy_text": "BosonRelay 订单 ord_1",
                "qr_image_url": "/api/v2/billing/orders/ord_1/qr.png",
                "poll_after_ms": 3000
              }],
              "usage": {"recent_events": []}
            }
            """.trimIndent()
        ).jsonObject

        val summary = parseBillingSummary(json)

        assertEquals("acct_1", summary.accountId)
        assertEquals(0, summary.wallet.balanceCents)
        assertEquals("plan_starter_monthly", summary.currentSubscription?.productId)
        assertEquals("Starter 月套餐", summary.products.plans.single().title)
        assertEquals(listOf("基础消息权益"), summary.products.plans.single().benefits)
        assertEquals("ord_1", summary.recentOrders.single().orderId)
        assertEquals("/api/v2/billing/orders/ord_1/qr.png", summary.recentOrders.single().qrImageUrl)
    }

    @Test
    fun formatsBillingAmountsForWalletDisplay() {
        assertEquals("¥19.00", formatBillingAmountCents(1900, "CNY"))
        assertEquals("USD 12.34", formatBillingAmountCents(1234, "USD"))
    }

    @Test
    fun paymentClipboardTextPrefersPlainPaymentUrlOverMultilineCopyText() {
        val order = BillingOrderResult(
            orderId = "ord_1",
            productId = "plan_starter_monthly",
            productKind = "plan",
            provider = "manual_qr",
            status = "pending",
            amountCents = 1900,
            currency = "CNY",
            expiresAt = "2026-06-01T00:15:00.000Z",
            paymentUrl = "https://pay.example.com/billing/pay?order_id=ord_1",
            copyText = "BosonRelay 订单 ord_1\n¥19.00\nhttps://pay.example.com/billing/pay?order_id=ord_1",
            qrImageUrl = "/api/v2/billing/orders/ord_1/qr.png",
            pollAfterMs = 3000,
        )

        assertEquals(order.paymentUrl, billingPaymentClipboardText(order))
    }

    @Test
    fun buildsLongRecordingAsrJobPayload() {
        val payload = buildLongRecordingAsrJobPayload(
            recordingId = "recording-1",
            filename = "meeting.wav",
            mimeType = "audio/wav",
            sizeBytes = 1024,
            recordingType = "meeting",
            asrProfileId = "volcengine-bigmodel",
            agentPrompt = "请整理会议纪要",
        )

        assertEquals("recording-1", payload["recording_id"]?.jsonPrimitive?.content)
        assertEquals("meeting.wav", payload["filename"]?.jsonPrimitive?.content)
        assertEquals("audio/wav", payload["mime_type"]?.jsonPrimitive?.content)
        assertEquals("1024", payload["size_bytes"]?.jsonPrimitive?.content)
        assertEquals("meeting", payload["recording_type"]?.jsonPrimitive?.content)
        assertEquals("volcengine-bigmodel", payload["asr_profile_id"]?.jsonPrimitive?.content)
        assertEquals("请整理会议纪要", payload["agent_prompt"]?.jsonPrimitive?.content)
    }

    @Test
    fun parsesLongRecordingAsrJobResponse() {
        val json = Json.parseToJsonElement(
            """
            {
              "job_id": "job-1",
              "status": "processing",
              "progress": 0.25,
              "upload_url": "/api/recordings/asr-jobs/job-1/chunks",
              "poll_after_ms": 1000
            }
            """.trimIndent()
        ).jsonObject

        val response = parseLongRecordingAsrJob(json)

        assertEquals("job-1", response.jobId)
        assertEquals("processing", response.status)
        assertEquals(0.25, response.progress)
        assertEquals("/api/recordings/asr-jobs/job-1/chunks", response.uploadUrl)
        assertEquals(1000, response.pollAfterMs)
    }
}
