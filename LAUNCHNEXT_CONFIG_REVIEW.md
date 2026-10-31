# 本机 LaunchNext 偏好参考

读取已安装 LaunchNext.app 的 Info.plist，确认偏好域为 com.roversx.launchnext。仅核对与本次需求相关的偏好，未修改该域或 Data.store。

读取结果：soundEffectsEnabled=true；enableAnimations=true；isFullscreenMode=false；launchpadBackgroundStyle=glass；animationDuration=0.3；windowAnimationDuration=0.25；iconLabelFontSize=11；iconScale=0.95。未设置的音效名在源码中回退为 Submarine、Glass、Tink。

Aplo 适配其 SoundManager 的系统音效选择与缓存方式，接入自身偏好和音量，移除语音依赖并限制连续导航音频重叠。保留 Aplo 已有显示方式和用户偏好，不整包导入 LaunchNext 配置。分类为 Aplo 的独立元数据／规则实现。
