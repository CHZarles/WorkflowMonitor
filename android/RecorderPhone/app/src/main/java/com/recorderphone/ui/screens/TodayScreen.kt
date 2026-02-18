package com.recorderphone.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Card
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp

data class BlockSummary(
    val id: String,
    val timeRange: String,
    val status: String,
    val top3: String,
    val note: String? = null
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TodayScreen() {
    val blocks = remember {
        listOf(
            BlockSummary(
                id = "b12",
                timeRange = "09:00–09:45",
                status = "✅ 已复盘",
                top3 = "VS Code 28m · github.com 9m · Slack 4m",
                note = "完成 X 模块接口；下一步补单测"
            ),
            BlockSummary(
                id = "b13",
                timeRange = "09:45–10:30",
                status = "⏳ 待复盘",
                top3 = "Figma 22m · docs.google.com 12m · WeChat 5m"
            )
        )
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Today") }
            )
        }
    ) { padding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
            contentPadding = PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            item {
                Text(
                    text = "Wireframe placeholder — see IA_WIREFRAMES.md",
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            items(blocks, key = { it.id }) { block ->
                BlockCard(block)
            }
        }
    }
}

@Composable
private fun BlockCard(block: BlockSummary) {
    Card {
        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(
                text = "${block.timeRange}  ${block.status}",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold
            )
            Text(
                text = block.top3,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            if (!block.note.isNullOrBlank()) {
                Text(
                    text = block.note,
                    style = MaterialTheme.typography.bodyMedium
                )
            }
        }
    }
}

