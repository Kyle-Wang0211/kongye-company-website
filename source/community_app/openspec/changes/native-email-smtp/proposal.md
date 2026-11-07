# 原生邮箱认证与官方 Send Email Hook

## 范围与身份

网站基线固定为 f7d71652f0d80de89e1dc71e1e8f0e7217e9ee00，复用已验证的 335007975ed0cabe13d71f35588d539d7f287103 邮箱接线，保留当前网站并发素材加载、流式发布与TUS上传改进。修改仅包含邮箱服务、控制器、验证码页参数与对应回归测试。SDK 和锁文件保持既有版本。

## 行为

注册调用 Supabase Auth signUp，原生 Auth 生成验证码并通过官方 Send Email Hook 交给既有阿里 DirectMail SDK 投递。待确认时只向验证码页传递邮箱，verifyOTP 的 email 类型建立会话。重发调用 resend 的 signup 类型。找回调用 resetPasswordForEmail，verifyOTP 的 recovery 类型建立会话后再 updateUser 修改密码。

旧方案在应用 pending_signups 中保存注册请求，验证后创建已确认用户，再用暂存密码登录。新方案在第一次 signUp 时创建待确认的 Auth 用户，邮箱确认前没有已验证会话。应用不继续管理 OTP、pending 密码和管理端密码修改。

PW_NATIVE_EMAIL_SMTP_READY 默认 false。关闭时阻止邮箱注册、重发、验证及找回的网络调用，并返回既有中文服务不可用错误。现有邮箱密码登录和手机流程沿用原入口。只有协调方完成真实原生 Hook 投递、正确/错误/过期码与恢复流程验收后才可在发布配置显式开启。测试构造参数仅用于隔离服务验证。

恢复验证码验证与密码更新是两个请求。第二个请求失败时，官方 SDK 可能已经拥有恢复会话，不能声称密码已修改或操作原子完成。用户重试可能需要重新发送恢复验证码。

## 切换说明

发布启用后，旧自定义邮件流程中尚未完成的验证码不能用于原生 Auth 验证。用户需要重新开始注册或找回流程并获取新验证码。本次源码改动不删除既有 pending_signups 数据库记录。

## 验收与边界

隔离 MockClient 观察官方 SDK 的 HTTP 请求，不实现本地验证码算法。必须验证 signup、resend、verify 和 recover 路径，email/recovery 类型，密码仅发送给 signup 和已认证 updateUser，错误验证码禁止密码更新，缺少会话禁止密码更新，以及手机/邮箱密码登录回归。请求数据均为合成账号。

停止条件包含测试失败、源码身份不符或邮箱文件并发写入。无设备写入、生产部署或依赖解析。Hook 实际送达由协调方单独取证。

## 来源

阿里 RDS 官方指南描述 SMTP 与邮箱模板 Token 配置。
https://help.aliyun.com/zh/rds/apsaradb-rds-for-postgresql/configure-email-authentication-and-templates-for-rds-supabase

官方 Supabase 邮箱验证码及密码恢复流程。
https://supabase.com/docs/guides/auth/auth-email-templates
https://supabase.com/docs/guides/auth/passwords

来源核查沿用 2026-11-06 route-assessment.md 和 source-captures.json，未推断托管实例的并发保证。

本次接线沿用 PW_NATIVE_EMAIL_SMTP_READY 配置名以保持兼容；该名称不表示投递实现仍为 SMTP。Hook 仅支持 signup/recovery，邮箱和手机登录仍使用密码。实际部署与真实发送尚未通过时保持 false。
