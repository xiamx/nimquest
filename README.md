## NimQuest

NimQuest 是一个运行在 长毛象 Mastodon 联邦宇宙 上的匿名问答系统。类似 Twitter 上的 Peing 。

- 提问者可以通过私信对 Mastodon 上的任何用户发起匿名提问。
- 回答者给出的回复会被 NimQuest 公开分享，回答者可以通过转嘟的方式把回复发布到自己的时间线上。

详见 [《NimQuest 使用指南》](https://shimo.im/docs/rykjKyVXJykyR6dy/)

### 安装和配置

1. NimQuest 由 Nim 语言编写，需要先[安装 Nim](https://nim-lang.org/install.html)。
2. 复制 `src/config.nim.example` 到 `src/config.nim`，填写 `clientAccessToken` 和 `apiRoot`。`clientAccessToken`是由用户生成的 mastodon 密匙。
3. 新建一个 sqlite3 数据库，命名其为 `db.sqlite3`，用 `init.sql` 中的 SQL 命令创建初始表和索引。
4. 用 `nimble run` 运行。

### 设计思路

这个项目是作者第一次用 Nim 写程序，用起来还是比较生涩，不具备教学意义。

主要思路如下：

- 无限循环获取 Bot 收到的新通知
  - 如果是提问问题就给回答人发私信
  - 如果是回答人回复就公开发表
  - 处理屏蔽和永久退出的指令 (NO and STOP)
- 用 Sqlite 在本地存储处理过的通知，以及屏蔽人之间的关系
- 为了代码读起来、思考起来方便，一切全部使用 Blocking IO 

未来扩展的思考：

- 使用 push notification 减少无效循环
- 用 Async IO 做并发，同时处理多个通知