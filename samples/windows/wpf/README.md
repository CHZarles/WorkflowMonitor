# WPF 资源字典模板（如何接入）

> 文件：
> - `RecorderTokens.xaml`：非颜色 token（间距/圆角/字号/动效）
> - `RecorderColors.Light.xaml`：浅色主题颜色与示例样式
> - `RecorderColors.Dark.xaml`：深色主题颜色

## App.xaml（最小接入示例）
把文件放到你的项目 `Themes/` 目录后：
```xml
<Application.Resources>
  <ResourceDictionary>
    <ResourceDictionary.MergedDictionaries>
      <ResourceDictionary Source="Themes/RecorderTokens.xaml" />
      <ResourceDictionary Source="Themes/RecorderColors.Light.xaml" />
      <!-- 或 Dark：Themes/RecorderColors.Dark.xaml -->
    </ResourceDictionary.MergedDictionaries>
  </ResourceDictionary>
</Application.Resources>
```

## 兼容性提示（很常见）
- 若你的 WPF 项目是 **.NET Framework**，`RecorderTokens.xaml` 里的 `xmlns:sys` 可能需要从 `System.Runtime` 改为 `mscorlib`。

## 运行时切换主题（建议做法）
- 用一个“ThemeManager”替换合并字典中的 Light/Dark 文件（保留 Tokens 常驻）。
- 颜色资源尽量用 `DynamicResource` 引用（示例样式里已如此），便于热切换。
