package me.weishu.kernelsu.ui.theme

import android.content.Context
import me.weishu.kernelsu.ksuApp

/**
 * SL-KernelSU 皮肤层。
 *
 * 皮肤 = 种子色 + 玻璃效果（模糊 / 悬浮底栏 / 底栏毛玻璃）的一组预设。
 * - 默认皮肤「水色玻璃拟态」在首次运行时自动套用一次；之后用户的手动设置不再被覆盖。
 * - 皮肤状态记录在 settings 偏好里（sl_skin），便于后续在设置页提供切换入口。
 */
object SlSkin {
    /** 水色（默认皮肤） */
    val WATER = 0xFF2E9BD6.toInt()

    /** 樱粉柔光 */
    val SAKURA = 0xFFFF9CA8.toInt()

    const val WATER_NAME = "water"
    const val SAKURA_NAME = "sakura"

    private const val PREFS_NAME = "settings"
    private const val KEY_APPLIED = "sl_skin_applied_v1"
    private const val KEY_SKIN = "sl_skin"

    private fun prefs() = ksuApp.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    /** 当前皮肤名（默认 water） */
    fun current(): String = prefs().getString(KEY_SKIN, WATER_NAME) ?: WATER_NAME

    /** 首次运行套用默认皮肤（仅一次；之后尊重用户手动修改） */
    fun applyDefaultOnce() {
        val p = prefs()
        if (p.getBoolean(KEY_APPLIED, false)) return
        p.edit()
            .putInt("key_color", WATER)
            .putBoolean("enable_blur", true)
            .putBoolean("enable_floating_bottom_bar", true)
            .putBoolean("enable_floating_bottom_bar_blur", true)
            .putString(KEY_SKIN, WATER_NAME)
            .putBoolean(KEY_APPLIED, true)
            .apply()
    }

    /** 切换皮肤：写入对应的种子色与玻璃效果组合 */
    fun applySkin(name: String) {
        val p = prefs()
        val seed = if (name == SAKURA_NAME) SAKURA else WATER
        p.edit()
            .putInt("key_color", seed)
            .putBoolean("enable_blur", true)
            .putBoolean("enable_floating_bottom_bar", true)
            .putBoolean("enable_floating_bottom_bar_blur", true)
            .putString(KEY_SKIN, name)
            .putBoolean(KEY_APPLIED, true)
            .apply()
    }
}