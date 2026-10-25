# iPhone/iPad 沿用墨水屏改版的界面语法，dp 按 1dp≈1pt，iPhone 是新的"窄屏"等级

iPhone/iPad 是彩色 LCD/OLED，微信读书手机版的语法（滚动、动效、彩色）和我们照抄的墨水屏版完全不同。我们决定 iOS 版**不**按手机版重做：沿用分页、无动画、黑白灰 chrome 的墨水屏改版，一个代码路径，参考基准仍是 Leaf5 实机截图；只有书的内容（插图、PDF 页、封面原图）按引擎输出彩色显示。代价是它在 LCD 上看起来"像墨水屏应用"。按手机版重做是另一个产品决定，不在本 ADR 范围。

dp 标尺：KOReader 的 dp 是 `min(w,h)/600`，任何竖屏都算 600dp 宽，在 iPhone 上会让整套界面缩到约 0.65 倍。我们决定 iOS 设备把 DPI 设成 1dp≈1pt：44dp 触控目标正好是 Apple 的 44pt，iPhone 成为约 390dp 宽的新"窄屏"等级，iPad 落在现有 6–10.3 寸比例范围内。DESIGN.md 的 Proportion Rule 不变，只是下限从 536dp 延到窄屏；现有按比例规则自然收敛的不写新规则，只为放不下的组件补规则。具体倍率在阶段 A 用模拟器验证后定（模拟器的 point 和 scale 与同型号真机一致）。

## Considered Options

- 不改 dp，靠用户调字号：界面 chrome（15dp 正文≈10pt、56dp 行≈36pt）在 iPhone 上不可用。
- 给 iPhone 单独一套布局：违反 Proportion Rule，等于维护第二套界面。
