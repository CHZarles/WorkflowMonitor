# WinUI 资源字典模板（如何接入）

> 文件：`RecorderTheme.xaml`（含 Light/Dark 的 ThemeDictionaries + tokens + 少量示例样式）

## App.xaml（最小接入示例）
把文件放到你的项目 `Themes/` 目录后：
```xml
<Application.Resources>
  <ResourceDictionary>
    <ResourceDictionary.MergedDictionaries>
      <ResourceDictionary Source="ms-appx:///Themes/RecorderTheme.xaml" />
    </ResourceDictionary.MergedDictionaries>
  </ResourceDictionary>
</Application.Resources>
```

## 使用方式
- 颜色/Brush：优先用 `{ThemeResource BrushAccent0}` 这类引用，自动跟随系统浅色/深色。
- 间距/圆角/字号：用 `{StaticResource Space4}` / `{StaticResource RadiusM}` / `{StaticResource FontSizeBody}`。

