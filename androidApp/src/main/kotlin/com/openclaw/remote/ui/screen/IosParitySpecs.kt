package com.openclaw.remote.ui.screen

data class IosParitySectionSpec(
    val title: String,
    val fields: List<String>,
    val footer: String? = null,
)

data class IosParityPageSpec(
    val title: String,
    val primaryAction: String? = null,
    val sections: List<IosParitySectionSpec>,
)

fun iosParitySpecFor(tab: AndroidRootTab): IosParityPageSpec =
    when (tab) {
        AndroidRootTab.AGENTS -> IosParityPageSpec(
            title = "Agent",
            primaryAction = "扫码添加",
            sections = listOf(
                IosParitySectionSpec(
                    title = "AI Provider",
                    fields = listOf("入口", "模型服务", "状态"),
                    footer = "这里不连接 Agent，也不会改动 Agent 对话历史。",
                ),
                IosParitySectionSpec(
                    title = "Agent",
                    fields = listOf("名称", "平台状态", "最近消息", "未读", "置顶"),
                ),
            ),
        )
        AndroidRootTab.RECORDINGS -> IosParityPageSpec(
            title = "录音",
            primaryAction = "开始录音",
            sections = listOf(
                IosParitySectionSpec(
                    title = "录音",
                    fields = listOf("时间", "来源", "录音类型", "ASR 文本", "事件", "提醒", "产物"),
                ),
            ),
        )
        AndroidRootTab.HEADSET -> IosParityPageSpec(
            title = "耳机",
            primaryAction = "耳机配对",
            sections = listOf(
                IosParitySectionSpec(
                    title = "耳机状态",
                    fields = listOf("设备", "连接状态", "电量"),
                ),
                IosParitySectionSpec(
                    title = "新功能",
                    fields = listOf("音频与 EQ", "手势快捷方式", "耳机定位", "固件更新"),
                ),
                IosParitySectionSpec(
                    title = "播放与控制",
                    fields = listOf("朗读 Agent 回复", "待机模式", "LED 灯"),
                ),
            ),
        )
        AndroidRootTab.SETTINGS -> IosParityPageSpec(
            title = "设置",
            sections = listOf(
                IosParitySectionSpec(
                    title = "账号",
                    fields = listOf("账号", "当前 Agent"),
                ),
                IosParitySectionSpec(
                    title = "偏好",
                    fields = listOf("深色模式", "AI 服务", "录音设置", "耳机设置"),
                ),
                IosParitySectionSpec(
                    title = "账号",
                    fields = listOf("钱包与套餐", "账号与安全", "切换账号", "退出登录"),
                ),
                IosParitySectionSpec(
                    title = "关于",
                    fields = listOf("APP 版本"),
                ),
            ),
        )
    }

fun recordingDetailParitySections(): List<IosParitySectionSpec> =
    listOf(
        IosParitySectionSpec(
            title = "录音",
            fields = listOf("时间", "状态", "录音类型", "来源", "音频", "ASR 文本"),
        ),
        IosParitySectionSpec(
            title = "Agent 回复",
            fields = listOf("状态", "尝试次数", "错误", "回复"),
        ),
        IosParitySectionSpec(
            title = "Agent 执行任务",
            fields = listOf("进度", "任务", "警告", "错误", "最终产物"),
        ),
        IosParitySectionSpec(
            title = "需要人完成的待办",
            fields = listOf("提醒", "待办"),
        ),
        IosParitySectionSpec(
            title = "导出的定时任务",
            fields = listOf("任务", "时间"),
        ),
        IosParitySectionSpec(
            title = "更多",
            fields = listOf("Prompt", "事件", "元数据"),
        ),
    )
