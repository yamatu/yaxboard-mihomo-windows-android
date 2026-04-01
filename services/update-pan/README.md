# update-pan

最小可用的 Go 更新托管程序，给 Xboard-Mihomo 提供两类能力：

- 托管安装包文件
- 提供客户端可直接调用的更新检查接口 `/api/v1/check-update`
- 生成远端 `config.json`，可直接填到 `xboard.config.yaml` 的 `remote_config.sources[].url`

## 目录结构

```text
services/update-pan/
  main.go
  config.example.json
  data/
    releases.example.json
    files/
      Xboard-Mihomo_1.0.1_windows.exe
      Xboard-Mihomo_1.0.1_android.apk
```

## 客户端对接

远端 `xboard.config.yaml` 示例：

```yaml
xboard:
  provider: mihomo
  remote_config:
    sources:
      - name: prod
        url: https://your-update.example.com/config.json
```

这个程序输出的 `config.json` 会同时带上：

- `panels`
- `subscription`（如果你配置了）
- `update`

更新检查接口返回结构为：

```json
{
  "latest_version": "1.0.1",
  "update_available": true,
  "download_url": "https://your-update.example.com/files/Xboard-Mihomo_1.0.1_windows.exe",
  "release_notes": "Windows hotfix build",
  "force_update": false
}
```

这和你当前客户端的 `UpdateService` 兼容。

## 使用方法

1. 复制配置模板

```powershell
Copy-Item .\config.example.json .\config.json
Copy-Item .\data\releases.example.json .\data\releases.json
New-Item -ItemType Directory -Force .\data\files
```

2. 把你的安装包放进 `data/files/`

文件名要和 `data/releases.json` 里的 `file` 对应。

3. 编辑 `config.json`

至少改这几个字段：

- `public_base_url`
- `panel_url`
- `subscription_url`，如果你有订阅入口

4. 编辑 `data/releases.json`

每个平台一条发布记录，当前支持：

- `windows`
- `android`
- `linux`
- `macos`

5. 启动

```powershell
go run . -config .\config.json
```

6. 验证

```powershell
Invoke-WebRequest http://127.0.0.1:8080/healthz
Invoke-WebRequest "http://127.0.0.1:8080/api/v1/check-update?version=1.0.0&platform=windows"
Invoke-WebRequest http://127.0.0.1:8080/config.json
```

## 部署建议

- 最简单：一台 Linux/Windows 云主机，反代到 Caddy 或 Nginx
- 也可以直接把这个程序放在你自己的下载机或 NAS 上跑
- 如果你已经有 CDN，可以让 CDN 回源这个程序

## 生产建议

- 用 HTTPS
- 把 `public_base_url` 配成外网最终访问地址
- 安装包文件名显式带版本号，避免缓存污染
- 每次发布新版本时只改 `data/releases.json` 并上传新文件

## 限制

- 这是最小版本，没有管理后台
- 发布记录当前走本地 JSON 文件，不走数据库
- 版本比较按数字段比较，适合 `1.2.3`、`1.2.3.4`
