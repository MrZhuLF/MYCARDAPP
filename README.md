# MYCARD

竖屏、离线的 Android 卡牌记录应用。Godot 4.7.2 / GDScript / Compatibility 3D / JSON + 原图本地存档。

## 运行

用 **Godot 4.7.2 Standard** 导入 `project.godot`，按 F6 运行当前场景或 F5 运行应用。不需要 Android Studio，也不需要 .NET。

主界面只保留货架、货币和功能导航。初次启动有 3 个可删除的示例系列与 1000 货币。右上角余额或「记账」可手动增减，支持备注。

## 功能

- 全屏 3D 货架，点牌包购买。银色压纹封口，正反封面独立替换，拆包动画。
- 每包数量与价格可编辑；按每种卡的剩余张数加权、不放回抽取。剩余库存不足整包时不收费。
- 系列与卡牌新建、编辑、搜索、删除。收藏保存设计快照，后续修改或删除设计不改变旧收藏。
- 图层编辑器：图片、文字、色块，自由拖动、缩放、旋转、透明颜色、锁定、显示、复制、删除及上下层级。支持撤销/重做画布编辑。
- PNG / JPEG / WebP / SVG / BMP / TGA 原文件导入，按内容哈希保存。等比例完整显示或等比例裁切；绝不重编码导入的原图。Windows 支持把图片拖到编辑器。
- 模板保存、应用、更新、重命名、删除；应用时按占位控件名称保留已填内容。文字框支持自动换行。
- 系列通用卡背与独立卡背；N / R / SR / SSR 默认评级对应无特效、金光、镭射、彩色，也可以单独选择特效。
- 卡牌/牌包可拖动绕 X / Y 轴旋转，卡牌可一键翻面。
- 离线账本、双代 JSON 存档、损坏恢复、含原图的 ZIP 备份和恢复。不申请网络权限。

## Android 构建

提交至 `main` 会运行 `.github/workflows/android.yml`。也可以在 GitHub → Actions → Android APK → Run workflow 手动触发。成功后下载 `MYCARD-Android-运行编号` artifact，解压安装 APK。目标为 ARM64 安卓设备。

流水线用官方 Godot 4.7.2 编辑器和同版本模板、JDK 17、Android SDK 35 构建测试签名 APK。测试签名通过 Actions 缓存复用；缓存失效后跨构建安装可能需要先导出备份、卸载旧版本、安装新版本再恢复。准备长期使用或发行前应配置固定签名密钥。

## 验证

```powershell
godot --headless --editor --import --quit
godot --headless res://tests/run.tscn -- --test
godot res://tests/run.tscn -- --test
```

测试隔离在 `user://test-run/`；第三条使用实际 GPU 渲染，截图保存到 `test-output/`。测试覆盖有限库存抽取、扣费、失败回滚、收藏快照、原图一致性、备份往返、损坏恢复和编辑器撤销重做。

## 数据与边界

- 应用数据目录：`user://collection.json`、`.bak`，图片在 `user://images/`。Windows 对应 `%APPDATA%/Godot/app_userdata/MYCARD/`。Android 在应用私有目录，卸载前请导出备份。
- 牌面逻辑尺寸 600 × 840，3D 预览纹理也为 600 × 840；原图单独原样保存，预览分辨率不代表原图被压缩。
- 这是首个可运行版本，未承诺达到商业模拟器的美术与性能水平。Android 原生文件选择、不同厂商机型的导入和大图内存占用需要真机验收。
- 当前图层数没有业务上限，但可用内存和 GPU 性能仍有限。删除设计不会自动清理图片，避免损坏收藏或模板引用。
- 参考用户提供的卡包结构自建程序化网格与封口材质；不分发原始第三方模型和其封面贴图。示例 SVG 为本项目制作。

架构和待验收项目见 [开发说明](docs/architecture.md)。
