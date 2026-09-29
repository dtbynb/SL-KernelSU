package me.weishu.kernelsu.ui.theme

import android.content.Context
import android.graphics.BitmapFactory
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Slider
import androidx.compose.material3.Switch
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
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.unit.dp
import me.weishu.kernelsu.ksuApp

/**
 * SL-KernelSU 应用内背景壁纸。
 *
 * 实现方式（透光层）：壁纸以较低不透明度铺在整个界面之上，配合主题色形成"壁纸透光"效果。
 * 这样 Material / Miuix 两种 UI 模式都能生效，且不需要改动页面背景（零风险）。
 * 变暗/提亮层随明暗主题自适应，保证文字可读性。
 */
object SlWallpaperPrefs {
    private const val PREFS = "settings"
    private const val KEY_ENABLED = "sl_wallpaper_enabled"
    private const val KEY_ID = "sl_wallpaper_id"
    private const val KEY_DIM = "sl_wallpaper_dim"
    private const val KEY_ALPHA = "sl_wallpaper_alpha"

    val enabled = mutableStateOf(true)
    val wallpaperId = mutableStateOf("water")
    /** 明暗调节（越大越暗/越柔） */
    val dim = mutableStateOf(0.35f)
    /** 壁纸透出强度 */
    val alpha = mutableStateOf(0.30f)

    private var loaded = false

    private fun prefs() = ksuApp.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun ensureLoaded() {
        if (loaded) return
        val p = prefs()
        enabled.value = p.getBoolean(KEY_ENABLED, true)
        wallpaperId.value = p.getString(KEY_ID, "water") ?: "water"
        dim.value = p.getFloat(KEY_DIM, 0.35f)
        alpha.value = p.getFloat(KEY_ALPHA, 0.30f)
        loaded = true
    }

    fun save() {
        prefs().edit()
            .putBoolean(KEY_ENABLED, enabled.value)
            .putString(KEY_ID, wallpaperId.value)
            .putFloat(KEY_DIM, dim.value)
            .putFloat(KEY_ALPHA, alpha.value)
            .apply()
    }
}

/** 内置壁纸：id / 显示名 / assets 路径 */
val slWallpapers = listOf(
    Triple("water", "水色波纹", "slksu/wallpapers/water.jpg"),
    Triple("sakura", "樱粉柔光", "slksu/wallpapers/sakura.jpg"),
    Triple("night", "夜幕水滴", "slksu/wallpapers/night.jpg"),
)

/** 按 id 读取内置壁纸位图（失败返回 null） */
fun slLoadWallpaper(id: String): ImageBitmap? {
    val path = slWallpapers.firstOrNull { it.first == id }?.third ?: return null
    return try {
        ksuApp.assets.open(path).use { BitmapFactory.decodeStream(it)?.asImageBitmap() }
    } catch (_: Exception) {
        null
    }
}

/** 壁纸层：包住整棵内容树（透光层画在内容之上）。参数名用 inner，避免与外层 content 冲突 */
@Composable
fun SlWallpaper(inner: @Composable () -> Unit) {
    SlWallpaperPrefs.ensureLoaded()
    val enabled by SlWallpaperPrefs.enabled
    val id by SlWallpaperPrefs.wallpaperId
    val dim by SlWallpaperPrefs.dim
    val alpha by SlWallpaperPrefs.alpha

    val dark = isInDarkTheme()
    val bitmap = remember(enabled, id) { if (!enabled) null else slLoadWallpaper(id) }

    Box(Modifier.fillMaxSize()) {
        inner()
        if (bitmap != null) {
            Box(Modifier.fillMaxSize()) {
                Image(
                    bitmap = bitmap,
                    contentDescription = null,
                    modifier = Modifier.fillMaxSize(),
                    contentScale = ContentScale.Crop,
                    alpha = alpha.coerceIn(0.05f, 0.6f),
                )
            }
            val scrim = if (dark) Color.Black else Color.White
            Box(
                Modifier
                    .fillMaxSize()
                    .background(scrim.copy(alpha = dim.coerceIn(0f, 0.8f)))
            )
        }
    }
}

/** 设置页「壁纸」行（含选择对话框） */
@Composable
fun SlWallpaperSettingRow() {
    SlWallpaperPrefs.ensureLoaded()
    var shown by remember { mutableStateOf(false) }
    val enabled by SlWallpaperPrefs.enabled
    val currentId by SlWallpaperPrefs.wallpaperId
    val currentName = slWallpapers.firstOrNull { it.first == currentId }?.second ?: "水色波纹"

    Column(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp)
    ) {
        Row(
            Modifier
                .fillMaxWidth()
                .clickable { shown = true }
                .padding(vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(Modifier.weight(1f)) {
                Text("壁纸", style = MaterialTheme.typography.bodyLarge)
                Text(
                    if (enabled) "已开启 · $currentName" else "已关闭",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Switch(
                checked = enabled,
                onCheckedChange = {
                    SlWallpaperPrefs.enabled.value = it
                    SlWallpaperPrefs.save()
                },
            )
        }
    }

    if (shown) {
        AlertDialog(
            onDismissRequest = { shown = false },
            title = { Text("壁纸") },
            text = {
                Column {
                    SlWallpaperPrefs.ensureLoaded()
                    val alphaState by SlWallpaperPrefs.alpha
                    val dimState by SlWallpaperPrefs.dim
                    Text("选择壁纸", style = MaterialTheme.typography.labelLarge)
                    Spacer(Modifier.height(8.dp))
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        slWallpapers.forEach { (wid, name, _) ->
                            val selected = wid == SlWallpaperPrefs.wallpaperId.value
                            val bmp = remember(wid) { slLoadWallpaper(wid) }
                            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                                Box(
                                    Modifier
                                        .size(56.dp)
                                        .clip(RoundedCornerShape(12.dp))
                                        .background(MaterialTheme.colorScheme.surfaceVariant)
                                        .clickable {
                                            SlWallpaperPrefs.wallpaperId.value = wid
                                            SlWallpaperPrefs.enabled.value = true
                                            SlWallpaperPrefs.save()
                                        }
                                ) {
                                    if (bmp != null) {
                                        Image(
                                            bitmap = bmp,
                                            contentDescription = name,
                                            modifier = Modifier.fillMaxSize(),
                                            contentScale = ContentScale.Crop,
                                            alpha = if (selected) 1f else 0.55f,
                                        )
                                    }
                                }
                                Spacer(Modifier.height(4.dp))
                                Text(
                                    name,
                                    style = MaterialTheme.typography.labelSmall,
                                    color = if (selected) MaterialTheme.colorScheme.primary
                                    else MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                        }
                    }
                    Spacer(Modifier.height(14.dp))
                    Text("透出强度 ${(alphaState * 100).toInt()}%", style = MaterialTheme.typography.labelLarge)
                    Slider(
                        value = alphaState,
                        onValueChange = { SlWallpaperPrefs.alpha.value = it },
                        onValueChangeFinished = { SlWallpaperPrefs.save() },
                        valueRange = 0.05f..0.6f,
                    )
                    Text("柔和度 ${(dimState * 100).toInt()}%", style = MaterialTheme.typography.labelLarge)
                    Slider(
                        value = dimState,
                        onValueChange = { SlWallpaperPrefs.dim.value = it },
                        onValueChangeFinished = { SlWallpaperPrefs.save() },
                        valueRange = 0f..0.8f,
                    )
                }
            },
            confirmButton = {
                TextButton(onClick = { shown = false }) { Text("完成") }
            },
        )
    }
}