package com.openclaw.remote.ui.screen

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.FileDownload
import androidx.compose.material.icons.filled.Fullscreen
import androidx.compose.material.icons.filled.RadioButtonUnchecked
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.openclaw.remote.data.ChatMessage
import com.openclaw.remote.rich.RichApprovalRequest
import com.openclaw.remote.rich.RichMarkdownTable
import com.openclaw.remote.rich.RichMessageBlock
import com.openclaw.remote.rich.detectApprovalRequest
import com.openclaw.remote.rich.parseRichMessageBlocks
import com.openclaw.remote.ui.theme.MochiTheme

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun MessageBubble(
    message: ChatMessage,
    isUser: Boolean,
    isSelectionMode: Boolean = false,
    isSelected: Boolean = false,
    onClick: () -> Unit = {},
    onCopy: () -> Unit = {},
    onQuote: () -> Unit = {},
    onSelect: () -> Unit = {},
    onSpeak: () -> Unit = {},
    onApprovalCommand: (String) -> Unit = {},
    isApprovalHandled: Boolean = false,
    onInspectApprovalCode: (RichApprovalRequest) -> Unit = {},
    onCopyTable: (RichMarkdownTable) -> Unit = {},
    onDownloadTable: (RichMarkdownTable) -> Unit = {},
    onFullscreenTable: (RichMarkdownTable) -> Unit = {},
    modifier: Modifier = Modifier,
) {
    val colors = MochiTheme.colors
    var menuExpanded by remember { mutableStateOf(false) }
    val approvalRequest = remember(message.content, isUser) {
        if (isUser) null else detectApprovalRequest(message.content)
    }
    val usesWideLayout = !isUser && (approvalRequest != null || message.content.prefersWideMessageLayout())
    val quotedMessage = remember(message.content) { parseLeadingQuotedMessage(message.content) }
    val displayContent = quotedMessage?.body ?: message.content

    Row(
        modifier = modifier
            .fillMaxWidth()
            .combinedClickable(
                onClick = onClick,
                onLongClick = { menuExpanded = true },
            ),
        horizontalArrangement = if (isUser) Arrangement.End else Arrangement.Start,
        verticalAlignment = Alignment.Bottom,
    ) {
        if (isSelectionMode) {
            Box(
                modifier = Modifier.width(28.dp),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    imageVector = if (isSelected) Icons.Filled.CheckCircle else Icons.Filled.RadioButtonUnchecked,
                    contentDescription = if (isSelected) "已选择" else "未选择",
                    tint = if (isSelected) colors.primary else colors.textSecondary,
                    modifier = Modifier.size(22.dp),
                )
            }
            Spacer(modifier = Modifier.width(4.dp))
        }

        Column(
            horizontalAlignment = if (isUser) Alignment.End else Alignment.Start,
            modifier = if (usesWideLayout) {
                Modifier.fillMaxWidth(0.96f)
            } else {
                Modifier.widthIn(max = 320.dp)
            },
        ) {
            if (approvalRequest != null) {
                ApprovalRequestCard(
                    request = approvalRequest,
                    isHandled = isApprovalHandled,
                    onCommand = onApprovalCommand,
                    onInspectCode = onInspectApprovalCode,
                )
            } else {
                Box(
                    modifier = Modifier
                        .clip(
                            when {
                                isUser -> RoundedCornerShape(
                                    topStart = 16.dp,
                                    topEnd = 4.dp,
                                    bottomStart = 16.dp,
                                    bottomEnd = 16.dp,
                                )
                                else -> RoundedCornerShape(
                                    topStart = 4.dp,
                                    topEnd = 16.dp,
                                    bottomStart = 16.dp,
                                    bottomEnd = 16.dp,
                                )
                            }
                        )
                        .background(if (isUser) colors.userBubble else colors.assistantBg)
                        .padding(horizontal = 14.dp, vertical = 10.dp),
                ) {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        if (quotedMessage != null) {
                            EmbeddedQuote(
                                summary = quotedMessage.quote,
                                isUser = isUser,
                            )
                        }

                        RichMarkdownMessageBody(
                            text = displayContent,
                            textColor = if (isUser) colors.userBubbleFg else colors.assistantFg,
                            onCopyTable = onCopyTable,
                            onDownloadTable = onDownloadTable,
                            onFullscreenTable = onFullscreenTable,
                        )
                    }
                }
            }

            Spacer(modifier = Modifier.height(3.dp))

            Text(
                text = message.timestamp,
                fontSize = 11.sp,
                color = colors.textSecondary,
            )

            DropdownMenu(
                expanded = menuExpanded,
                onDismissRequest = { menuExpanded = false },
            ) {
                DropdownMenuItem(
                    text = { Text("复制") },
                    onClick = {
                        menuExpanded = false
                        onCopy()
                    },
                )
                DropdownMenuItem(
                    text = { Text("引用") },
                    onClick = {
                        menuExpanded = false
                        onQuote()
                    },
                )
                DropdownMenuItem(
                    text = { Text("朗读") },
                    onClick = {
                        menuExpanded = false
                        onSpeak()
                    },
                )
                DropdownMenuItem(
                    text = { Text("选择") },
                    onClick = {
                        menuExpanded = false
                        onSelect()
                    },
                )
            }
        }
    }
}

@Composable
private fun RichMarkdownMessageBody(
    text: String,
    textColor: Color,
    onCopyTable: (RichMarkdownTable) -> Unit,
    onDownloadTable: (RichMarkdownTable) -> Unit,
    onFullscreenTable: (RichMarkdownTable) -> Unit,
) {
    val blocks = remember(text) { parseRichMessageBlocks(text) }

    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        blocks.forEach { block ->
            when (block) {
                is RichMessageBlock.Text -> {
                    if (block.value.isNotBlank()) {
                        Text(
                            text = parseBoldMarkdown(block.value),
                            fontSize = 15.sp,
                            lineHeight = 22.sp,
                            color = textColor,
                        )
                    }
                }
                is RichMessageBlock.Table -> MarkdownTableCard(
                    table = block.table,
                    textColor = textColor,
                    onCopy = onCopyTable,
                    onDownload = onDownloadTable,
                    onFullscreen = onFullscreenTable,
                )
            }
        }
    }
}

@Composable
private fun MarkdownTableCard(
    table: RichMarkdownTable,
    textColor: Color,
    onCopy: (RichMarkdownTable) -> Unit,
    onDownload: (RichMarkdownTable) -> Unit,
    onFullscreen: (RichMarkdownTable) -> Unit,
) {
    val colors = MochiTheme.colors

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(8.dp))
            .border(0.5.dp, colors.divider, RoundedCornerShape(8.dp)),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .background(colors.surface.copy(alpha = 0.72f))
                .padding(start = 10.dp, end = 6.dp, top = 6.dp, bottom = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                text = "表格",
                fontSize = 12.sp,
                fontWeight = FontWeight.Medium,
                color = textColor.copy(alpha = 0.72f),
                modifier = Modifier.weight(1f),
            )
            TableToolButton(Icons.Filled.ContentCopy, "复制表格") { onCopy(table) }
            TableToolButton(Icons.Filled.FileDownload, "下载表格") { onDownload(table) }
            TableToolButton(Icons.Filled.Fullscreen, "全屏查看表格") { onFullscreen(table) }
        }

        Box(
            modifier = Modifier
                .fillMaxWidth()
                .horizontalScroll(rememberScrollState()),
        ) {
            MarkdownTableGrid(
                table = table,
                textColor = textColor,
                modifier = Modifier.padding(bottom = 1.dp),
            )
        }
    }
}

@Composable
private fun TableToolButton(
    imageVector: ImageVector,
    contentDescription: String,
    onClick: () -> Unit,
) {
    IconButton(
        onClick = onClick,
        modifier = Modifier.size(32.dp),
    ) {
        Icon(
            imageVector = imageVector,
            contentDescription = contentDescription,
            modifier = Modifier.size(18.dp),
        )
    }
}

@Composable
fun MarkdownTableGrid(
    table: RichMarkdownTable,
    textColor: Color,
    modifier: Modifier = Modifier,
) {
    val columnWidths = remember(table) { table.columnCharacterWidths() }

    Column(modifier = modifier) {
        MarkdownTableRow(table.headers, columnWidths = columnWidths, isHeader = true, textColor = textColor)
        table.rows.forEach { row ->
            MarkdownTableRow(row, columnWidths = columnWidths, isHeader = false, textColor = textColor)
        }
    }
}

@Composable
private fun MarkdownTableRow(
    cells: List<String>,
    columnWidths: List<Int>,
    isHeader: Boolean,
    textColor: Color,
) {
    val colors = MochiTheme.colors

    Row(horizontalArrangement = Arrangement.Start) {
        cells.forEachIndexed { index, cell ->
            val width = (columnWidths.getOrElse(index) { 8 } * 12).dp
            Text(
                text = parseBoldMarkdown(cell.ifEmpty { " " }),
                fontSize = 13.sp,
                lineHeight = 19.sp,
                fontWeight = if (isHeader) FontWeight.SemiBold else FontWeight.Normal,
                color = textColor,
                modifier = Modifier
                    .width(width)
                    .background(if (isHeader) colors.surface.copy(alpha = 0.45f) else Color.Transparent)
                    .border(0.5.dp, colors.divider.copy(alpha = 0.65f))
                    .padding(horizontal = 10.dp, vertical = 8.dp),
            )
        }
    }
}

@Composable
private fun ApprovalRequestCard(
    request: RichApprovalRequest,
    isHandled: Boolean,
    onCommand: (String) -> Unit,
    onInspectCode: (RichApprovalRequest) -> Unit,
) {
    val colors = MochiTheme.colors

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(8.dp))
            .background(colors.surface)
            .border(0.5.dp, colors.divider, RoundedCornerShape(8.dp)),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .background(Color(0xFF5E2D0A))
                .padding(horizontal = 12.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Icon(
                imageVector = Icons.Filled.Warning,
                contentDescription = null,
                tint = Color(0xFFFFC24A),
                modifier = Modifier.size(18.dp),
            )
            Text(
                text = request.title,
                fontSize = 15.sp,
                fontWeight = FontWeight.SemiBold,
                color = Color(0xFFFFC24A),
            )
        }

        Column(
            modifier = Modifier.padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            if (request.command.isNotBlank()) {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(8.dp))
                        .background(Color.Black.copy(alpha = 0.55f))
                        .border(0.5.dp, Color.White.copy(alpha = 0.14f), RoundedCornerShape(8.dp))
                        .clickable { onInspectCode(request) }
                        .padding(10.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Text(
                        text = request.commandPreview,
                        fontSize = 13.sp,
                        lineHeight = 19.sp,
                        fontFamily = FontFamily.Monospace,
                        color = Color.White.copy(alpha = 0.88f),
                        maxLines = 4,
                    )
                    HorizontalDivider(color = Color.White.copy(alpha = 0.18f), thickness = 0.5.dp)
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(
                            text = "${request.lineCount} 行代码",
                            fontSize = 12.sp,
                            fontWeight = FontWeight.Medium,
                            color = colors.textSecondary,
                            modifier = Modifier.weight(1f),
                        )
                        Icon(
                            imageVector = Icons.Filled.ChevronRight,
                            contentDescription = "查看代码",
                            tint = colors.textSecondary,
                            modifier = Modifier.size(18.dp),
                        )
                    }
                }
            }

            if (request.reason.isNotBlank()) {
                Text(
                    text = "Reason: ${request.reason}",
                    fontSize = 14.sp,
                    lineHeight = 20.sp,
                    color = colors.textPrimary,
                )
            }

            if (isHandled) {
                Text(
                    text = "已处理，本条审批不会再次发送",
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Medium,
                    color = colors.textSecondary,
                )
            }

            ApprovalButtonGrid(isDisabled = isHandled, onCommand = onCommand)
        }
    }
}

@Composable
private fun ApprovalButtonGrid(
    isDisabled: Boolean,
    onCommand: (String) -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            ApprovalCommandButton(
                title = "Allow Once",
                command = "/approve",
                primary = true,
                enabled = !isDisabled,
                modifier = Modifier.weight(1f),
                onCommand = onCommand,
            )
            ApprovalCommandButton(
                title = "Session",
                command = "/approve session",
                enabled = !isDisabled,
                modifier = Modifier.weight(1f),
                onCommand = onCommand,
            )
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            ApprovalCommandButton(
                title = "Always",
                command = "/approve always",
                enabled = !isDisabled,
                modifier = Modifier.weight(1f),
                onCommand = onCommand,
            )
            ApprovalCommandButton(
                title = "Deny",
                command = "/deny",
                destructive = true,
                enabled = !isDisabled,
                modifier = Modifier.weight(1f),
                onCommand = onCommand,
            )
        }
    }
}

@Composable
private fun ApprovalCommandButton(
    title: String,
    command: String,
    modifier: Modifier = Modifier,
    primary: Boolean = false,
    destructive: Boolean = false,
    enabled: Boolean = true,
    onCommand: (String) -> Unit,
) {
    val colors = MochiTheme.colors

    if (primary) {
        Button(
            onClick = { onCommand(command) },
            enabled = enabled,
            modifier = modifier.heightIn(min = 42.dp),
            colors = ButtonDefaults.buttonColors(
                containerColor = colors.primary,
                contentColor = colors.onPrimary,
            ),
            contentPadding = PaddingValues(horizontal = 10.dp, vertical = 8.dp),
            shape = RoundedCornerShape(8.dp),
        ) {
            Icon(Icons.Filled.Check, contentDescription = null, modifier = Modifier.size(16.dp))
            Spacer(modifier = Modifier.width(7.dp))
            Text(title, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
        }
    } else {
        OutlinedButton(
            onClick = { onCommand(command) },
            enabled = enabled,
            modifier = modifier.heightIn(min = 42.dp),
            colors = ButtonDefaults.outlinedButtonColors(
                contentColor = if (destructive) colors.recordingRed else colors.textPrimary,
            ),
            border = BorderStroke(
                width = 1.dp,
                color = if (destructive) colors.recordingRed.copy(alpha = 0.8f) else colors.divider,
            ),
            contentPadding = PaddingValues(horizontal = 10.dp, vertical = 8.dp),
            shape = RoundedCornerShape(8.dp),
        ) {
            Text(
                text = title,
                fontSize = 14.sp,
                fontWeight = FontWeight.SemiBold,
                maxLines = 1,
                textAlign = TextAlign.Center,
            )
        }
    }
}

@Composable
fun ApprovalCodeInspectorDialog(
    request: RichApprovalRequest,
    onDismiss: () -> Unit,
    onCopyLine: (String) -> Unit,
    onCopyAll: (String) -> Unit,
) {
    val colors = MochiTheme.colors
    val lines = remember(request) {
        if (request.codeLines.isEmpty() && request.command.isNotBlank()) {
            listOf(request.command)
        } else {
            request.codeLines
        }
    }

    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false),
    ) {
        Surface(
            modifier = Modifier.fillMaxSize(),
            color = colors.background,
        ) {
            Column(modifier = Modifier.fillMaxSize()) {
                DialogTopBar(
                    title = "${lines.size} 行代码",
                    onDismiss = onDismiss,
                    trailing = {
                        TextButton(
                            onClick = { onCopyAll(request.command) },
                            enabled = request.command.isNotBlank(),
                        ) {
                            Icon(Icons.Filled.ContentCopy, contentDescription = null, modifier = Modifier.size(16.dp))
                            Spacer(modifier = Modifier.width(6.dp))
                            Text("复制全部")
                        }
                    },
                )

                if (lines.isEmpty()) {
                    Box(
                        modifier = Modifier.fillMaxSize(),
                        contentAlignment = Alignment.Center,
                    ) {
                        Text("没有解析到代码", color = colors.textSecondary, fontSize = 15.sp)
                    }
                } else {
                    Column(
                        modifier = Modifier
                            .fillMaxSize()
                            .verticalScroll(rememberScrollState())
                            .horizontalScroll(rememberScrollState())
                            .padding(16.dp),
                    ) {
                        lines.forEachIndexed { index, line ->
                            CodeLineRow(
                                lineNumber = index + 1,
                                line = line,
                                alternating = index % 2 == 0,
                                onCopyLine = onCopyLine,
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun CodeLineRow(
    lineNumber: Int,
    line: String,
    alternating: Boolean,
    onCopyLine: (String) -> Unit,
) {
    val colors = MochiTheme.colors

    Row(
        modifier = Modifier
            .background(if (alternating) colors.surface.copy(alpha = 0.78f) else colors.inputBg.copy(alpha = 0.58f))
            .padding(horizontal = 10.dp, vertical = 9.dp),
        verticalAlignment = Alignment.Top,
    ) {
        Text(
            text = lineNumber.toString(),
            fontSize = 12.sp,
            fontFamily = FontFamily.Monospace,
            fontWeight = FontWeight.Medium,
            color = colors.textSecondary,
            textAlign = TextAlign.End,
            modifier = Modifier.width(42.dp),
        )
        Spacer(modifier = Modifier.width(12.dp))
        Text(
            text = line.ifEmpty { " " },
            fontSize = 13.sp,
            lineHeight = 19.sp,
            fontFamily = FontFamily.Monospace,
            color = colors.textPrimary,
            modifier = Modifier.widthIn(min = 220.dp),
        )
        Spacer(modifier = Modifier.width(16.dp))
        IconButton(
            onClick = { onCopyLine(line) },
            modifier = Modifier.size(28.dp),
        ) {
            Icon(
                imageVector = Icons.Filled.ContentCopy,
                contentDescription = "复制第 $lineNumber 行",
                tint = colors.textSecondary,
                modifier = Modifier.size(16.dp),
            )
        }
    }
}

@Composable
fun MarkdownTableFullscreenDialog(
    table: RichMarkdownTable,
    onDismiss: () -> Unit,
    onCopy: () -> Unit,
    onDownload: () -> Unit,
) {
    val colors = MochiTheme.colors

    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false),
    ) {
        Surface(
            modifier = Modifier.fillMaxSize(),
            color = colors.background,
        ) {
            Column(modifier = Modifier.fillMaxSize()) {
                DialogTopBar(
                    title = "表格",
                    onDismiss = onDismiss,
                    trailing = {
                        IconButton(onClick = onCopy) {
                            Icon(Icons.Filled.ContentCopy, contentDescription = "复制表格")
                        }
                        IconButton(onClick = onDownload) {
                            Icon(Icons.Filled.FileDownload, contentDescription = "下载表格")
                        }
                    },
                )

                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .verticalScroll(rememberScrollState())
                        .horizontalScroll(rememberScrollState())
                        .padding(16.dp),
                ) {
                    MarkdownTableGrid(table = table, textColor = colors.textPrimary)
                }
            }
        }
    }
}

@Composable
private fun DialogTopBar(
    title: String,
    onDismiss: () -> Unit,
    trailing: @Composable RowScope.() -> Unit,
) {
    val colors = MochiTheme.colors

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(colors.surface)
            .padding(horizontal = 8.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        IconButton(onClick = onDismiss) {
            Icon(Icons.Filled.Close, contentDescription = "关闭", tint = colors.icon)
        }
        Text(
            text = title,
            fontSize = 16.sp,
            fontWeight = FontWeight.SemiBold,
            color = colors.textPrimary,
            modifier = Modifier.weight(1f),
        )
        trailing()
    }
}

private data class ParsedQuotedMessage(
    val quote: String,
    val body: String,
)

private fun parseLeadingQuotedMessage(text: String): ParsedQuotedMessage? {
    val lines = text.lines()
    if (lines.firstOrNull()?.trimStart()?.startsWith(">") != true) return null

    val quoteLines = mutableListOf<String>()
    var index = 0
    while (index < lines.size) {
        val trimmed = lines[index].trimStart()
        if (!trimmed.startsWith(">")) break
        quoteLines += trimmed.removePrefix(">").trim()
        index += 1
    }

    while (index < lines.size && lines[index].isBlank()) {
        index += 1
    }

    val quote = quoteLines.joinToString("\n").trim()
    val body = lines.drop(index).joinToString("\n").trim()
    if (quote.isBlank() || body.isBlank()) return null
    return ParsedQuotedMessage(quote, body)
}

@Composable
private fun EmbeddedQuote(
    summary: String,
    isUser: Boolean,
) {
    val colors = MochiTheme.colors
    val contentColor = if (isUser) colors.userBubbleFg else colors.assistantFg

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(8.dp))
            .background(colors.surface.copy(alpha = 0.28f))
            .padding(horizontal = 10.dp, vertical = 8.dp),
        verticalAlignment = Alignment.Top,
    ) {
        Box(
            modifier = Modifier
                .width(3.dp)
                .height(38.dp)
                .clip(RoundedCornerShape(2.dp))
                .background(contentColor.copy(alpha = 0.45f)),
        )

        Spacer(modifier = Modifier.width(8.dp))

        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = "引用",
                fontSize = 11.sp,
                color = contentColor.copy(alpha = 0.68f),
                fontWeight = FontWeight.Medium,
            )
            Text(
                text = summary,
                fontSize = 12.sp,
                lineHeight = 17.sp,
                color = contentColor.copy(alpha = 0.74f),
                maxLines = 3,
            )
        }
    }
}

private fun String.prefersWideMessageLayout(): Boolean {
    if (contains("```")) return true
    return parseRichMessageBlocks(this).any { it is RichMessageBlock.Table }
}

private fun parseBoldMarkdown(text: String): AnnotatedString {
    val regex = Regex("\\*\\*(.+?)\\*\\*")
    return buildAnnotatedString {
        var lastIndex = 0
        regex.findAll(text).forEach { match ->
            append(text.substring(lastIndex, match.range.first))
            withStyle(SpanStyle(fontWeight = FontWeight.SemiBold)) {
                append(match.groupValues[1])
            }
            lastIndex = match.range.last + 1
        }
        if (lastIndex < text.length) {
            append(text.substring(lastIndex))
        }
    }
}
