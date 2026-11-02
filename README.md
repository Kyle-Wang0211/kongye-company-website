# 空也科技公司官网

北京空也科技有限公司（Beijing Kongye Technology Co., Ltd）的公司与产品展示网站源码。

- 正式域名：https://kongye.space/
- 产品：窗后城（开发中的 iOS 应用）
- 新版静态文件：`docs/`
- 社区网页的 Flutter 源码与构建说明：`source/community_app/`

## 发布状态

正式域名 `kongye.space` 已绑定该仓库的 GitHub Pages。发布源为 `main` 分支的 `/docs` 目录，推送后由 GitHub Pages 自动发布。网站无需安装依赖或构建。

域名的 HTTPS 证书由 GitHub Pages 自动管理。提交推送、Pages 发布成功和浏览器功能验收是独立步骤；当前实际验收状态以部署记录为准。

## 更新官网

修改 `docs/` 内的 HTML、CSS、JavaScript 或图片，提交并推送到 `main`，由 GitHub Pages 更新官网。发布分支为 `main`，目录为 `/docs`。

当前网页提供正式发布的用户协议、隐私政策、平台公约及三维作品发布与审核说明，入口位于首页“支持与联系”和页脚。

社区作品、账号和评论由共用后端提供；后端源码保存在独立的 `pocketworld-backend` 仓库。网页允许公开浏览与分享，点赞和发表评论需要登录。部署后的浏览器下载、登录与评论链路仍须独立验收，不能仅以编译或 Pages 成功判定通过。

第三方三维示例素材的来源和许可见 [ATTRIBUTION.md](ATTRIBUTION.md)。
