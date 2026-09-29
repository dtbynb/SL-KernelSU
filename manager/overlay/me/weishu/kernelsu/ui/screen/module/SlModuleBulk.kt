package me.weishu.kernelsu.ui.screen.module

import android.os.Environment
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Checklist
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Checkbox
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.topjohnwu.superuser.ShellUtils
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import me.weishu.kernelsu.data.repository.ModuleRepositoryImpl
import me.weishu.kernelsu.ui.util.getRootShell
import me.weishu.kernelsu.ui.util.toggleModule
import me.weishu.kernelsu.ui.util.uninstallModule
import java.io.File

/**
 * SL-KernelSU 模块批量管理。
 *
 * 模块页顶栏一个按钮 → 弹出清单（多选）→ 批量启用 / 禁用 / 卸载 / 导出（tar.gz 到下载目录）。
 * 卸载带二次确认并列出待卸载清单；导出的压缩包可通过「模块」页或文件管理器恢复。
 */
private data class SlModItem(val id: String, val name: String, val enabled: Boolean)

@Composable
fun SlModuleBulkButton() {
    var shown by remember { mutableStateOf(false) }
    IconButton(onClick = { shown = true }) {
        Icon(Icons.Filled.Checklist, contentDescription = "批量管理")
    }
    if (shown) {
        SlModuleBulkDialog(onDismiss = { shown = false })
    }
}

@Composable
private fun SlModuleBulkDialog(onDismiss: () -> Unit) {
    val scope = rememberCoroutineScope()
    var loading by remember { mutableStateOf(true) }
    var items by remember { mutableStateOf<List<SlModItem>>(emptyList()) }
    val selected = remember { mutableStateMapOf<String, Boolean>() }
    var busy by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf("") }
    var confirmUninstall by remember { mutableStateOf(false) }

    suspend fun reload() {
        loading = true
        val list = withContext(Dispatchers.IO) {
            try {
                ModuleRepositoryImpl().getModules().getOrNull()
                    ?.map { SlModItem(it.id, it.name, it.enabled) }
                    ?: emptyList()
            } catch (_: Exception) {
                emptyList()
            }
        }
        items = list
        loading = false
    }

    LaunchedEffect(Unit) { reload() }

    fun selectedIds(): List<String> = selected.filter { it.value }.keys.toList()

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("模块批量管理") },
        text = {
            Column(Modifier.heightIn(max = 420.dp)) {
                if (loading) {
                    LinearProgressIndicator(Modifier.fillMaxWidth())
                }
                Text(
                    "已选 ${selected.count { it.value }} / ${items.size}" +
                        if (busy) "（处理中…）" else "",
                    style = MaterialTheme.typography.labelLarge,
                )
                Row {
                    TextButton(onClick = { items.forEach { selected[it.id] = true } }) { Text("全选") }
                    TextButton(onClick = { selected.clear() }) { Text("清空") }
                }
                LazyColumn {
                    items(items) { m ->
                        Row(
                            Modifier
                                .fillMaxWidth()
                                .clickable { selected[m.id] = !(selected[m.id] ?: false) }
                                .padding(vertical = 2.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Checkbox(
                                checked = selected[m.id] == true,
                                onCheckedChange = { selected[m.id] = it },
                            )
                            Column(Modifier.padding(start = 4.dp)) {
                                Text(m.name, style = MaterialTheme.typography.bodyMedium)
                                Text(
                                    if (m.enabled) "已启用" else "已禁用",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                        }
                    }
                }
                if (message.isNotEmpty()) {
                    Text(message, style = MaterialTheme.typography.bodySmall)
                }
            }
        },
        confirmButton = {
            Row {
                TextButton(
                    enabled = !busy && selectedIds().isNotEmpty(),
                    onClick = {
                        val ids = selectedIds()
                        scope.launch {
                            busy = true
                            val ok = withContext(Dispatchers.IO) { ids.all { toggleModule(it, true) } }
                            message = if (ok) "已批量启用 ${ids.size} 个模块（重启后生效）" else "部分模块启用失败"
                            reload(); busy = false
                        }
                    },
                ) { Text("启用") }
                TextButton(
                    enabled = !busy && selectedIds().isNotEmpty(),
                    onClick = {
                        val ids = selectedIds()
                        scope.launch {
                            busy = true
                            val ok = withContext(Dispatchers.IO) { ids.all { toggleModule(it, false) } }
                            message = if (ok) "已批量禁用 ${ids.size} 个模块（重启后生效）" else "部分模块禁用失败"
                            reload(); busy = false
                        }
                    },
                ) { Text("禁用") }
                TextButton(
                    enabled = !busy && selectedIds().isNotEmpty(),
                    onClick = { confirmUninstall = true },
                ) { Text("卸载") }
                TextButton(
                    enabled = !busy && selectedIds().isNotEmpty(),
                    onClick = {
                        val ids = selectedIds()
                        scope.launch {
                            busy = true
                            val ok = withContext(Dispatchers.IO) {
                                try {
                                    val dir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
                                    val file = File(dir, "slksu-modules-${System.currentTimeMillis()}.tar.gz")
                                    val cmd = "tar -czf ${file.absolutePath} -C /data/adb/modules ${ids.joinToString(" ")}"
                                    ShellUtils.fastCmd(getRootShell(), cmd)
                                    file.exists()
                                } catch (_: Exception) {
                                    false
                                }
                            }
                            message = if (ok) "已导出到下载目录（slksu-modules-*.tar.gz）" else "导出失败"
                            busy = false
                        }
                    },
                ) { Text("导出") }
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("关闭") }
        },
    )

    if (confirmUninstall) {
        val ids = selectedIds()
        val names = items.filter { ids.contains(it.id) }.joinToString("\n") { "· ${it.name}" }
        AlertDialog(
            onDismissRequest = { confirmUninstall = false },
            title = { Text("确认批量卸载？") },
            text = { Text("将卸载 ${ids.size} 个模块：\n\n$names\n\n卸载后可在「模块」页使用撤销功能恢复。") },
            confirmButton = {
                TextButton(onClick = {
                    confirmUninstall = false
                    scope.launch {
                        busy = true
                        withContext(Dispatchers.IO) { ids.forEach { uninstallModule(it) } }
                        message = "已卸载 ${ids.size} 个模块"
                        selected.clear()
                        reload()
                        busy = false
                    }
                }) { Text("确认卸载") }
            },
            dismissButton = {
                TextButton(onClick = { confirmUninstall = false }) { Text("取消") }
            },
        )
    }
}