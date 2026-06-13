package com.openclaw.remote.ui.screen

import com.openclaw.remote.data.AiServiceChoice
import org.junit.Assert.assertEquals
import org.junit.Test

class RootTabsStateTest {
    @Test
    fun rootTabLabelsMatchIosVisibleTabs() {
        assertEquals(
            listOf("Agent", "录音", "耳机", "设置"),
            AndroidRootTab.entries.map { it.label },
        )
    }

    @Test
    fun rootNavigationStateStartsOnAgentList() {
        val state = RootNavigationState()

        assertEquals(AndroidRootTab.AGENTS, state.selectedTab)
        assertEquals(null, state.openChatProfileId)
        assertEquals(false, state.isProviderChatOpen)
    }

    @Test
    fun providerChatRouteSelectsRouterAndByokClients() {
        assertEquals(
            ProviderChatRoute.ROUTER,
            providerChatRouteFor(AiServiceChoice(mode = "router", providerId = "router")),
        )
        assertEquals(
            ProviderChatRoute.OPENAI_COMPATIBLE,
            providerChatRouteFor(AiServiceChoice(mode = "byok", providerId = "openai-compatible")),
        )
        assertEquals(
            ProviderChatRoute.ANTHROPIC,
            providerChatRouteFor(AiServiceChoice(mode = "byok", providerId = "claude")),
        )
        assertEquals(
            ProviderChatRoute.AGENT_DISABLED,
            providerChatRouteFor(AiServiceChoice(mode = "agent", providerId = "agent")),
        )
    }

    @Test
    fun agentTabSectionsMatchIosHeadOrder() {
        val spec = iosParitySpecFor(AndroidRootTab.AGENTS)

        assertEquals("Agent", spec.title)
        assertEquals("扫码添加", spec.primaryAction)
        assertEquals(
            listOf("AI Provider", "Agent"),
            spec.sections.map { it.title },
        )
        assertEquals(
            listOf("名称", "平台状态", "最近消息", "未读", "置顶"),
            spec.sections[1].fields,
        )
    }

    @Test
    fun recordingDetailSectionsMatchIosHeadOrder() {
        val sections = recordingDetailParitySections()

        assertEquals(
            listOf("录音", "Agent 回复", "Agent 执行任务", "需要人完成的待办", "导出的定时任务", "更多"),
            sections.map { it.title },
        )
    }

    @Test
    fun headsetTabSectionsMatchIosHeadOrder() {
        val spec = iosParitySpecFor(AndroidRootTab.HEADSET)

        assertEquals("耳机", spec.title)
        assertEquals("耳机配对", spec.primaryAction)
        assertEquals(
            listOf("耳机状态", "新功能", "播放与控制"),
            spec.sections.map { it.title },
        )
    }

    @Test
    fun settingsTabSectionsMatchIosHeadOrder() {
        val spec = iosParitySpecFor(AndroidRootTab.SETTINGS)

        assertEquals("设置", spec.title)
        assertEquals(
            listOf("账号", "偏好", "账号", "关于"),
            spec.sections.map { it.title },
        )
        assertEquals(
            listOf("深色模式", "AI 服务", "录音设置", "耳机设置"),
            spec.sections[1].fields,
        )
    }
}
