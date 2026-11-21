# 帖子动图滚动压测

用同一套本地 HTML 和图片启动指定提交的 `ThreadDetailScreen`。Mock APK 的包名是 `com.example.south_plus_gif_bench14`，可与正式版同时安装。测试会重启这个 mock 应用。

在带 Android SDK 的 Flutter 3.38.4 环境中，从仓库根目录构建两个 profile 包。两个包须用同一签名。MuMu 使用 `android-x64`，真机可用 `android-arm64`。

```bash
bash scripts/gif_perf/build.sh e5f0001 /tmp/before.apk android-x64
bash scripts/gif_perf/build.sh HEAD /tmp/after.apk android-x64
```

在能访问 MuMu 的主机上安装 Pillow，并用同一批图片依次测量。采样需要 `adb shell su -c id` 能读应用进程的 `/proc`。脚本用 `adb reverse` 连接主机的 TCP 18765 端口。

```bash
adb -s 127.0.0.1:5555 install -r /tmp/before.apk
python scripts/gif_perf/run.py before --cases one-gif two-gif group-gif spread-gif group-still group-manual
adb -s 127.0.0.1:5555 install -r /tmp/after.apk
python scripts/gif_perf/run.py after --fixtures before/fixtures --cases one-gif two-gif group-gif spread-gif group-still group-manual two-play
```

`group` 把 100 张图放在同一楼，`spread` 每楼一张。图片交替使用 1200×1600 和 800×600，动图 24 帧，每帧 50 ms。静态对照只保留同一张图的第一帧，仍编码为 GIF。`group-manual` 打开「手动点击加载」，`two-play` 打开「正文静止时播放」。每轮使用新 URL，滚动到底后关闭详情页。要复测逐图重绘边界，可在构建基线包的命令末尾加 `boundary`。

每个用例输出一份 JSON。首屏请求数来自 HTTP 服务，解码尺寸来自 `RawImage`。CPU 以单核为 100%，PSS 来自进程的 `smaps_rollup`。Flutter 帧预算按 60 Hz 计算，`total` 含 vsync 到 raster 完成的排队时间。分阶段记录空闲、程序驱动的滚动和退出，不测手指到屏幕的输入延迟。
