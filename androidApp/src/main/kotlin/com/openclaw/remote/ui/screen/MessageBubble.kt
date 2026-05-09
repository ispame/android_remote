package com.openclaw.remote.ui.screen

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.openclaw.remote.data.ChatMessage
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
    modifier: Modifier = Modifier
) {
    val colors = MochiTheme.colors
    var menuExpanded by remember { mutableStateOf(false) }
    val usesWideLayout = !isUser && message.content.prefersWideMessageLayout()
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
            Text(
                text = if (isSelected) "●" else "○",
                fontSize = 22.sp,
                color = if (isSelected) colors.primary else colors.textSecondary,
                modifier = Modifier.width(28.dp),
            )
            Spacer(modifier = Modifier.width(4.dp))
        }

        Column(
            horizontalAlignment = if (isUser) Alignment.End else Alignment.Start,
            modifier = if (usesWideLayout) {
                Modifier.fillMaxWidth(0.96f)
            } else {
                Modifier.widthIn(max = 320.dp)
            }
        ) {
            Box(
                modifier = Modifier
                    .clip(
                        when {
                            isUser -> RoundedCornerShape(
                                topStart = 16.dp,
                                topEnd = 4.dp,
                                bottomStart = 16.dp,
                                bottomEnd = 16.dp
                            )
                            else -> RoundedCornerShape(
                                topStart = 4.dp,
                                topEnd = 16.dp,
                                bottomStart = 16.dp,
                                bottomEnd = 16.dp
                            )
                        }
                    )
                    .background(if (isUser) colors.userBubble else colors.assistantBg)
                    .padding(horizontal = 14.dp, vertical = 10.dp)
            ) {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    if (quotedMessage != null) {
                        EmbeddedQuote(
                            summary = quotedMessage.quote,
                            isUser = isUser,
                        )
                    }

                    Text(
                        text = parseBoldMarkdown(displayContent),
                        fontSize = 15.sp,
                        lineHeight = 22.sp,
                        color = if (isUser) colors.userBubbleFg else colors.assistantFg,
                    )
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
                .background(contentColor.copy(alpha = 0.45f))
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
    val lines = lines()
    return lines.windowed(size = 2, step = 1).any { pair ->
        val header = pair[0].split("|").map { it.trim() }.filter { it.isNotEmpty() }
        val separator = pair[1].split("|").map { it.trim() }.filter { it.isNotEmpty() }
        header.size >= 2 && separator.size >= 2 && separator.all { cell ->
            cell.trim(':').length >= 3 && cell.trim(':').all { it == '-' }
        }
    }
}

@Composable
private fun AvatarChip(
    label: String,
    bgColor: androidx.compose.ui.graphics.Color,
    textColor: androidx.compose.ui.graphics.Color,
    modifier: Modifier = Modifier
) {
    Box(
        modifier = modifier
            .size(32.dp)
            .clip(CircleShape)
            .background(bgColor),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = label,
            fontSize = 12.sp,
            fontWeight = FontWeight.Medium,
            color = textColor,
        )
    }
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
