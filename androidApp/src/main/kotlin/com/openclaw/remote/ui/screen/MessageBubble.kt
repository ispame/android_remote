package com.openclaw.remote.ui.screen

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
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

@Composable
fun MessageBubble(
    message: ChatMessage,
    isUser: Boolean,
    modifier: Modifier = Modifier
) {
    val colors = MochiTheme.colors

    Row(
        modifier = modifier.fillMaxWidth(),
        horizontalArrangement = if (isUser) Arrangement.End else Arrangement.Start,
        verticalAlignment = Alignment.Bottom,
    ) {
        if (!isUser) {
            AvatarChip(label = "M", bgColor = colors.secondary, textColor = colors.onSecondary)
            Spacer(modifier = Modifier.width(8.dp))
        }

        Column(
            horizontalAlignment = if (isUser) Alignment.End else Arrangement.Start,
            modifier = Modifier.widthIn(max = 280.dp)
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
                Text(
                    text = parseBoldMarkdown(message.content),
                    fontSize = 15.sp,
                    lineHeight = 22.sp,
                    color = if (isUser) colors.userBubbleFg else colors.assistantFg,
                )
            }

            Spacer(modifier = Modifier.height(3.dp))

            Text(
                text = message.timestamp,
                fontSize = 11.sp,
                color = colors.textSecondary,
            )
        }

        if (isUser) {
            Spacer(modifier = Modifier.width(8.dp))
            AvatarChip(label = "你", bgColor = colors.primary, textColor = colors.onPrimary)
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
