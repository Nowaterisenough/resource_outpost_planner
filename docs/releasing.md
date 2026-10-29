# 自动发布 / Automatic releases

## 中文

推送到 `main` 会自动发布到 **GitHub Releases** 和 **Factorio Mod Portal**。无需手动创建标签或先改版本号。

流程依次执行：

1. 用 Lua 5.2 执行离线回归，检查 Lua 语法、翻译键和蓝图矩阵，同时测试发布失败恢复。
2. 读取 `info.json` 和当前提交历史中的版本标签。如果版本未手动提高，自动增加补丁号，例如 `1.10.3 → 1.10.4`。
3. 生成 `changelog.txt` 新条目：`feat` 归入 Features、`fix` 归入 Bugfixes、`perf` 归入 Optimizations，其他提交归入 Changes。日期取源提交日期，保证重跑结果稳定。
4. 构建可复现 ZIP，保存 SHA-256 校验文件和发布说明，再验证包内全部源文件。
5. 原子推送版本提交和 `vX.Y.Z` 标签。版本提交只包含 `info.json`、`changelog.txt`，并带 `[skip ci]`；使用 `GITHUB_TOKEN` 推送，不会递归触发发布。
6. 创建 GitHub 草稿并上传 ZIP、`SHA256SUMS`，上传同一 ZIP 到模组站，校验成功后公开 GitHub Release。

如果需要调整主版本或次版本，可以在推送前提高 `info.json` 版本，并在 `changelog.txt` 顶部写对应版本的条目。已有条目会保留；没有条目时自动生成。版本提交由机器人回写 `main`，本地继续开发前应先 `git pull --ff-only`。

### 仓库配置

- 添加 Actions repository secret **`FACTORIO_API_KEY`**，使用具有 **`ModPortal: Upload Mods`** 权限的模组站 API key。不要把 key 写入 workflow、日志或仓库文件。
- `GITHUB_TOKEN` 由 GitHub 自动提供。发布 job 请求 `contents: write`，用于推送版本提交、标签和创建 Release。
- 如果启用分支保护或仓库规则，必须允许此工作流向 `main` 写入版本提交和创建版本标签。禁止直接推送的规则会使发布停止。
- workflow 位于 [`.github/workflows/release.yml`](../.github/workflows/release.yml)。本地 `secret/`、`dist/`、测试和 CI 文件不进入模组 ZIP。

### 预演、失败与重试

Actions → **Release** → **Run workflow**，保留默认 `dry_run=true`，可只执行检查并生成下载工件。取消该选项会从 `main` 正式发布；推送 `main` 始终正式发布。

失败后优先使用 **Re-run failed jobs**。已成功创建的标签、草稿、附件和模组站版本会核对校验值后复用；遇到同版本不同内容会失败，禁止覆盖。完整重跑也会生成相同版本和相同 ZIP。

运行中的发布不会被新推送取消。若发布版本提交前 `main` 已更新，旧任务会跳过，由最新任务发布累计变更。GitHub 只保留一个等待中的同组任务，因此密集推送可能合并成一次发布。若旧任务已完成版本提交，重跑仍可补全该版本，但不会把较旧版本设为 latest。

如果缺少 API key，发布 job 会在创建版本提交、标签或草稿之前失败。GitHub 的版本推送若遭到拒绝，也不会上传到模组站。两个发布平台没有跨平台事务：如果模组站成功后 GitHub 失败，重跑会复用模组站版本并完成 GitHub 发布。

本地检查与预演：

```sh
python -m pip install -r requirements-dev.txt
python scripts/check-release.py
python scripts/release.py prepare --output dist/release-preview
```

输出目录需使用新目录，避免覆盖已有 ZIP。`prepare` 临时更新版本元数据打包，结束后恢复源文件。正式发布脚本由 Actions 调用。离线回归不启动游戏，不能代替涉及布局、预览、放置时的 Factorio 原生测试。

## English

Every push to `main` automatically validates, versions, packages and publishes the mod to **GitHub Releases** and **Factorio Mod Portal**. No tag or manual version bump is required.

The workflow increments the patch version from the highest version tag in the source history, unless `info.json` already specifies a newer version. It preserves an existing changelog entry for that version; otherwise it generates one from commits since the previous release, grouped by `feat`, `fix`, `perf` and other changes. The source commit date and deterministic ZIP metadata make retries reproducible.

Configure the repository secret **`FACTORIO_API_KEY`** with **`ModPortal: Upload Mods`** permission. GitHub supplies `GITHUB_TOKEN`; the publish job requests `contents: write`. Branch and tag rules must permit the bot to push version metadata to `main` and create release tags. The generated commit uses `[skip ci]`, and pushes made with `GITHUB_TOKEN` do not trigger another workflow. Pull `main` before continuing local development.

The tested archive, checksum and notes are retained as workflow artifacts. Publication atomically pushes a version commit and tag, creates a GitHub draft, uploads the same ZIP to Factorio, then publishes the GitHub release after verification. Retries reuse matching artifacts and refuse to overwrite different contents at the same version. Use **Re-run failed jobs** after an interrupted publication.

A newer push supersedes an older run that has not yet committed its version. Rapid pushes can be combined into a single release; an in-progress publication is not cancelled. Retrying an older draft does not promote it over a higher version.

For a preview, use **Actions → Release → Run workflow** with the default `dry_run=true`. Unchecking it publishes from `main`. The local commands above run the same offline checks and prepare an archive without leaving version edits in the checkout. Native Factorio scenarios remain separate from these CI checks.
