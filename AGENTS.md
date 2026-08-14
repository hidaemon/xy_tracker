# xy_tracker 插件开发约定

## 客户端版本约束（重要）
- 目标客户端：魔兽世界 70 TBC，20 周年纪念服（Classic TBC Anniversary）
- 客户端版本号：2.5.6
- Interface 版本：20506（build 69110）
- 所有 API 和接口必须严格以该客户端为基准。

## 聊天装备链接许愿查询规则（重要）
- 69110 客户端聊天装备链接点击主要使用各个 `ChatFrame` 的 `OnHyperlinkClick`；不能只依赖 `SetItemRef`。
- `SetItemRef` 和 `ChatFrame_OnHyperlinkShow` 只能作为兼容回调，必须同时兼容 `ChatFrame1` 到 `ChatFrameN` 的 `OnHyperlinkClick`。
- 触发条件必须严格为 `Shift + 右键`，兼容 `RightButton` 和 `BUTTON2`，且只处理包含 `item:` 的聊天装备链接。
- 聊天链接可能是 `item:` 原始格式，也可能是完整的 `|Hitem:...|h[装备名称]|h|r` 格式，不能只判断字符串是否以 `item:` 开头。
- 装备匹配必须先按物品 ID 比对；没有物品 ID 时，再对名称进行清洗后比对。
- 名称清洗至少包括：颜色代码、超链接控制符、方括号、空格，以及物品等级后缀（例如 `(138)`）。
- 不得把背包、银行或装备 Tooltip 的点击作为聊天装备查询触发源；Tooltip 仅用于悬停显示许愿统计。

## 新协议全量同步规则（重要）
- 小型控制消息上限为 240 字节；必须由 `AceComm-3.0` 发送，不得直接调用 `SendAddonMessage` 发送新协议消息。
- 全量同步必须使用 `LibSerialize → LibDeflate → Chomp`；Chomp 内部使用 `ChatThrottleLib` 节流并完成分片和重组，不得再实现自有压缩、Base64、分片或重组算法。
- 团员必须在 Chomp 收齐完整数据后完成 LibDeflate 解码、解压、LibSerialize 反序列化和记录校验，成功后才能替换本地许愿表。
- 旧版新协议的 `BEGIN → REC → END` 与 `PART/LS*` 自定义分片不再作为当前新协议发送格式；老客户端仅通过隔离的 `xy_legacy.lua` 兼容老协议。
- `Libs/LibStub`、`CallbackHandler-1.0`、`ChatThrottleLib`、`LibSerialize`、`LibDeflate`、`AceComm-3.0` 和 `Chomp` 必须在主文件前加载。
- `xy_snapshot.lua` 只负责第三方库编排和数据校验；`xy_tracker.lua` 只保留协议路由和模块调用，避免通讯实现再次耦合。

## 安全执行与小退流程规则（重要）
- 每次修改插件代码或 TOC 声明，都必须递增 `xy_tracker.toc` 的 `## Version`，并同步更新源码目录和实际客户端目录。
- 不得向暴雪全局 `StaticPopupDialogs` 表写入插件自定义对话框；该表会被游戏菜单的小退/退出流程共享，写入后可能导致 `ADDON_ACTION_FORBIDDEN` 和 `callback()` 保护错误。需要确认或输入时，使用插件自己的普通 `Frame` 弹窗。
- `PLAYER_LOGOUT` 只允许设置本地持久化标记和停止插件内部队列；必须停止 `OnUpdate`、Roll 通报、AceComm/Chomp 待发消息和交易处理，不得在该事件中调用聊天、插件通讯或其他可能受保护的 API。
- 不得通过修改暴雪游戏菜单、`StaticPopup` 或其他安全框架的脚本来实现小退提示；小退提示必须与游戏菜单隔离，并且所有弹出窗口都使用插件命名空间。
- 小退后的清空确认必须区分“本次客户端会话已提示”和“重新启动客户端”；`PLAYER_LOGOUT` 在切换人物时也可能触发，不能每次无条件设置提示标记。
