# Flutter UI 规范提示词（临床App）
# 每次让 Claude 开发新页面时，把此文档贴在 prompt 开头

---

## 项目 UI 规范（必须严格遵守）

本项目使用统一的轻量简约医疗工具风格，参考豆包App / iOS HIG。
所有页面必须使用以下规范，禁止自行引入不一致的样式。

---

### 颜色（直接使用 AppColors 类）

| 用途 | 值 |
|------|-----|
| 主背景 | `AppColors.bgPrimary` (#FFFFFF) |
| 次级背景/卡片底 | `AppColors.bgSecondary` (#F5F5F7) |
| 分割线 | `AppColors.divider` (#F3F4F6) |
| 主强调色（按钮/选中） | `AppColors.primary` (#3B82F6) |
| 正文 | `AppColors.textPrimary` (#1A1A1A) |
| 次要文字 | `AppColors.textSecondary` (#6B7280) |
| 辅助/占位文字 | `AppColors.textHint` (#9CA3AF) |
| 危险/警告 | `AppColors.danger` / `AppColors.warning` |

> 禁止硬编码颜色值，统一使用 AppColors。

---

### 字体（直接使用 AppTextStyles 类）

| 场景 | 样式 |
|------|------|
| 页面标题 | `AppTextStyles.pageTitle`（17px/700） |
| 列表项标题 | `AppTextStyles.listTitle`（15px/600） |
| 正文 | `AppTextStyles.body`（14px/400，行高1.6） |
| 辅助说明 | `AppTextStyles.caption`（13px，#9CA3AF） |
| 标签 | `AppTextStyles.label`（12px/500） |

---

### 间距 & 圆角（使用 AppSpacing 类）

- 页面水平边距：`AppSpacing.xl`（20px）
- 卡片内边距：`EdgeInsets.all(AppSpacing.lg)`（16px）
- 元素间距：`AppSpacing.sm/md/lg`（8/12/16px）
- 卡片圆角：`AppSpacing.radiusCard`（14px）
- 按钮圆角：`AppSpacing.radiusButton`（10px）
- 输入框圆角：`AppSpacing.radiusInput`（10px）

---

### 组件规范

**卡片**
```dart
Container(
  decoration: BoxDecoration(
    color: AppColors.bgCard,
    borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
    boxShadow: AppShadows.card,
  ),
  padding: EdgeInsets.all(AppSpacing.lg),
)
```

**主按钮**：使用 `ElevatedButton`，高度48px，宽铺满，样式已在 ThemeData 定义

**次级按钮**：使用 `OutlinedButton`，背景 `AppColors.bgSecondary`

**输入框**：使用 `TextField`，样式已在 InputDecorationTheme 定义，无需额外设置

**列表项**：使用 `ListTile`，左侧头像44px圆形，标题15px/600，副标题13px/#9CA3AF

**头像占位**：使用 `AppColors.avatarPalette` 按索引循环取色

**分割线**：使用 `const Divider()` 即可

---

### 禁止事项

- ❌ 禁止使用 `elevation` 大于 0 的卡片阴影（用 BoxShadow 替代）
- ❌ 禁止使用渐变色背景（医疗场景需保持专业克制）
- ❌ 禁止使用填充式(filled)图标，统一使用 outline 风格
- ❌ 禁止硬编码任何颜色、字号、间距值
- ❌ 禁止在非强调场景使用 primary 色（蓝色仅用于主操作）

---

### 页面结构模板

```dart
Scaffold(
  backgroundColor: AppColors.bgSecondary,  // 页面底色用浅灰
  appBar: AppBar(title: Text('页面标题')),   // 已由 ThemeData 统一处理
  body: SafeArea(
    child: SingleChildScrollView(
      padding: EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 内容卡片用白色，页面底色用浅灰，形成自然层次
        ],
      ),
    ),
  ),
)
```

---

使用方式：在 main.dart 中引入主题
```dart
MaterialApp(
  theme: AppTheme.light,
  ...
)
```
