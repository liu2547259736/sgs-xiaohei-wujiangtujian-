package com.sgsheroes.sgs_heroes

import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // 全屏（edge-to-edge）：内容延伸到状态栏与导航栏后面。
        //
        // Flutter 侧的 SystemUiMode.edgeToEdge 在部分系统版本上不会真正落到
        // setDecorFitsSystemWindows(false)，这里显式再设一次，覆盖 Android 5~14。
        // 安全区由页面 CSS 的 --sb-top / --sb-bottom 自己避让
        // （壳通过 window.__sgsShellInsets 把真实高度喂进去），
        // 所以这里不需要给内容留 padding。
        WindowCompat.setDecorFitsSystemWindows(window, false)

        // 刘海 / 挖孔屏：允许内容进入到挖孔区域，否则状态栏那条会多出一段黑边。
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val attrs = window.attributes
            attrs.layoutInDisplayCutoutMode =
                WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
            window.attributes = attrs
        }
    }
}
