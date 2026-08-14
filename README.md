# 乘风破浪-许愿插件（重制版）

团队许愿、DKP、Roll 点和历史许愿管理插件，适用于国服 TBC 2.5.6 / 20506、69110 客户端。

## 当前版本

- 插件版本：4.0.1
- TOC 版本：20506、69110
- 新协议：`XYTRK2`
- 老协议：`XY_COMMAND`、`XY_INITDKP`、`XY_RESET`、`XY_SYNC`

## 安装

将整个 `xy_tracker` 文件夹复制到：

```text
World of Warcraft/_anniversary_/Interface/AddOns/
```

最终目录结构应为：

```text
Interface/AddOns/xy_tracker/xy_tracker.toc
Interface/AddOns/xy_tracker/Libs/LibStub/LibStub.lua
Interface/AddOns/xy_tracker/Libs/LibSerialize/LibSerialize.lua
Interface/AddOns/xy_tracker/Libs/CallbackHandler-1.0/CallbackHandler-1.0.lua
Interface/AddOns/xy_tracker/Libs/ChatThrottleLib/ChatThrottleLib.lua
Interface/AddOns/xy_tracker/Libs/LibDeflate/LibDeflate.lua
Interface/AddOns/xy_tracker/Libs/AceComm-3.0/AceComm-3.0.lua
Interface/AddOns/xy_tracker/Libs/Chomp/Internal.lua
Interface/AddOns/xy_tracker/Libs/Chomp/Public.lua
Interface/AddOns/xy_tracker/Libs/Chomp/StringManip.lua
Interface/AddOns/xy_tracker/xy_tracker.lua
Interface/AddOns/xy_tracker/xy_snapshot.lua
Interface/AddOns/xy_tracker/xy_legacy.lua
Interface/AddOns/xy_tracker/xy_ui.lua
Interface/AddOns/xy_tracker/xy_trade.lua
```

进入角色选择界面后确认插件已勾选。如果显示“过期插件”，请勾选“加载过期插件”。

## 打开方式

- 点击小地图旁的插件图标。
- 小地图图标可以使用左键拖动，并沿小地图外圈移动。
- 松开鼠标后会自动保存位置。
- 直接单击小地图图标可以打开或关闭主窗口。
- 也可以使用命令：

```text
/xyt
```

## 页面说明

插件有三个竖向页签：

### 许愿

用于团队成员登记装备许愿。

主要列：

- 角色名
- 职业
- 许愿内容
- 分数
- 操作
- 达成

管理员可以：

- 开始许愿
- 停止许愿
- 重置团队许愿
- 初始化 DKP
- 刷新团队成员
- 通报未许愿成员
- 导出许愿数据
- 点击角色行中的 `+` 或 `-` 调整分数
- 点击“达成”复选框标记许愿是否完成
- 点击列头进行排序
- 点击角色名时高亮当前行
- 点击“测试25条”生成测试数据

普通队员可以查看数据，但不能执行管理员操作。

### Roll

Roll 页面用于团队 Roll 点。

功能包括：

- 开始 Roll
- 倒计时通报
- 清空 Roll 结果
- 显示所有参与者的 Roll 点
- 按分数从高到低排列
- 同分时显示并列最高
- 每个玩家独立一行发送通报
- 可设置是否重复 Roll 通知
- 可选择团队或小队频道发送通知

Roll 结束后，列表会保留本次 Roll 结果，切换页签不会影响许愿页面数据。

### 历史许愿

历史页面用于查看重置前保存的许愿信息。

功能包括：

- 左侧显示每次重置的日期和时间
- 每次重置对应一份完整许愿记录
- 点击左侧日期，右侧显示对应记录
- 点击“导出许愿表”，导出当前选中的重置日期对应的完整记录
- 右侧显示角色名、职业、许愿内容和达成状态
- 可清空历史记录

导出内容会显示在可移动的多行文本框中，文本框打开后可以直接使用 Ctrl+A、Ctrl+C 复制。

重置时间格式为：

```text
月-日 小时:分
```

## 装备交易分配

管理员与队员打开交易窗口后，交易窗口右侧会吸附显示“装备交易分配”面板，按钮从上到下为：

- `-1`
- `-2`
- `-3`
- `-4`
- `达成`

前四个按钮会在交易成功后扣除对应 DKP；一次交易中有多件装备时，仍按按钮选择的分数只扣除一次，并保存装备清单。`达成`按钮会在交易成功后将当前交易对象的许愿标记为已达成，不额外建立交易历史记录。该面板属于独立交易模块，不改变许愿页和 Roll 页布局。

## 通讯协议

### 自动协商

默认情况下，插件打开或进入团队时会：

1. 向团队管理员探测新协议。
2. 收到管理员的新协议响应后，使用新协议。
3. 在规定时间内没有收到管理员响应，切换为老协议。
4. 底部状态显示：
   - 绿色“新协议”
   - 红色“老协议”

普通队员之间的消息不会被当作管理员响应。

### 新协议全量同步

管理员先使用 `LibSerialize` 序列化全量记录，再由 `LibDeflate` 压缩并编码，最后交给 `Chomp.SmartAddonMessage` 发送。Chomp 内部使用 `ChatThrottleLib` 节流，并负责插件频道的分片、重组和完整消息回调；团员仅在解码、解压、反序列化与记录校验成功后，才会替换本地许愿表。插件不再维护自写压缩、Base64 或 `PART/LS*` 分片协议。

### 强制新协议

当团队全部使用重制版插件时，可以关闭协议判断，直接使用新协议：

```text
/xyt protocol on
```

### 恢复自动协商

```text
/xyt protocol auto
```

或：

```text
/xyt protocol off
```

### 查看协议模式

```text
/xyt protocol
```

### 老版本兼容说明

老协议代码独立放在 `xy_legacy.lua` 中，便于后续移除。

如果管理员没有安装新版本插件：

- 新插件会自动切换为老协议。
- 如果当前新插件是管理员，会主动发送老协议数据。
- 如果当前新插件只是普通队员，老版本协议没有主动请求同步功能，需要等待老版本管理员下一次刷新、重置或同步。

## 命令列表

| 命令 | 功能 |
| --- | --- |
| `/xyt` | 打开或关闭主窗口 |
| `/xyt start` | 开始许愿 |
| `/xyt stop` | 停止许愿 |
| `/xyt reset` | 重置许愿 |
| `/xyt refresh` | 刷新团队成员 |
| `/xyt announce` | 通报未许愿成员 |
| `/xyt export` | 导出许愿数据 |
| `/xyt show` | 输出当前许愿列表 |
| `/xyt clean` | 清空当前列表 |
| `/xyt mode` | 切换物品链接识别模式 |
| `/xyt protocol` | 查看通讯协议模式 |
| `/xyt protocol on` | 强制新协议 |
| `/xyt protocol auto` | 自动协商协议 |
| `/xyt query 角色名` | 查询指定角色许愿信息 |

## 权限

插件管理员通常为：

- 团队领袖
- 具有团队管理权限的指定人员
- 小队队长

管理员负责：

- 维护团队成员列表
- 修改 DKP
- 执行重置
- 发送同步数据
- 发起许愿和 Roll 点流程

普通队员主要用于：

- 查看许愿列表
- 提交自己的许愿
- 查看 Roll 结果
- 查看历史许愿

## 数据保存

插件会保存以下内容：

- 当前许愿数据
- 默认 DKP
- 物品链接识别模式
- 许愿历史
- 重置历史
- Roll 设置
- 协议强制开关
- 小地图按钮位置

SavedVariables 位于客户端 WTF 保存目录中。删除 SavedVariables 会清除本地历史记录、Roll 设置和小地图位置。

## 常见问题

### 团队中点击刷新没有数据

请确认：

1. 团队成员已经完成加载。
2. 当前角色处于团队或小队中。
3. 管理员已经打开插件。
4. 底部协议状态是否为“新协议”或“老协议”。
5. 如果使用老版本管理员，请等待管理员下一次重置或同步。

### 协议状态显示老协议

这表示没有收到管理员的新协议响应。可能原因：

- 管理员没有安装重制版。
- 管理员插件未加载。
- 当前不在团队或小队中。
- 团队通讯 API 被其他插件或客户端限制。
- 协议正在等待老版本管理员下一次同步。

### 小地图图标不在原位置

按住小地图图标左键拖动。图标会沿小地图外圈移动，松开后自动保存。

### 出现 Lua 错误

建议：

1. 输入 `/console scriptErrors 1`。
2. 记录完整错误信息。
3. 确认客户端版本为 20506、69110。
4. 确认没有混用旧目录中的同名 Lua 文件。
5. 重载界面：

```text
/reload
```

## 文件说明

| 文件 | 用途 |
| --- | --- |
| `xy_tracker.toc` | 插件描述、版本和加载顺序 |
| `Libs/LibStub/LibStub.lua` | 第三方库版本管理器 |
| `Libs/LibSerialize/LibSerialize.lua` | 第三方表结构序列化库（MIT） |
| `Libs/CallbackHandler-1.0/CallbackHandler-1.0.lua` | AceComm/Chomp 的回调分发依赖 |
| `Libs/ChatThrottleLib/ChatThrottleLib.lua` | 官方插件频道节流依赖 |
| `Libs/LibDeflate/LibDeflate.lua` | 第三方压缩与 WoW 插件频道编码库 |
| `Libs/AceComm-3.0/AceComm-3.0.lua` | 新协议控制消息与自动分片通讯库 |
| `Libs/Chomp/*.lua` | 全量同步的安全编码、分片、重组和通讯封装 |
| `xy_tracker.lua` | 主逻辑、数据、通讯和命令 |
| `xy_snapshot.lua` | 新协议全量同步的第三方库编排和完整性校验 |
| `xy_legacy.lua` | 老版本通讯兼容模块 |
| `xy_ui.lua` | 主界面、页签、列表和弹窗 |
| `xy_trade.lua` | 交易和 DKP 扣分辅助 |

## 测试建议

正式使用前建议用两个角色测试：

1. 两个角色都安装重制版，确认显示绿色“新协议”。
2. 管理员使用旧版本，确认新插件在协商后显示红色“老协议”。
3. 测试许愿、重置、DKP 修改和历史记录。
4. 测试 Roll 点是否显示所有人并按分数排序。
5. 测试小地图图标拖动和重载后的保存效果。

## 兼容目标

本插件代码按 TBC 2.5.6 / 20506、69110 客户端 API 编写，避免使用正式服后续版本专用 API。

---
