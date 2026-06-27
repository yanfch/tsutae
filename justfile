# tsutae 常用命令
set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

xcode_project := "App/Tsutae/Tsutae.xcodeproj"
xcode_scheme := "Tsutae"
derived_data := ".build/xcode"

default:
    @just --list

# 构建 Core（静默模式；失败时输出日志尾部）
build-core:
    @log_file=$(mktemp -t tsutae-build-core.XXXXXX.log); \
    if (cd Packages/TsutaeCore && swift build >"$log_file" 2>&1); then \
      echo "BUILD_CORE_OK"; \
    else \
      echo "BUILD_CORE_FAILED"; \
      echo "log: $log_file"; \
      tail -n 80 "$log_file"; \
      exit 1; \
    fi

# 测试 Core（静默模式；失败时输出日志尾部）
test-core:
    @log_file=$(mktemp -t tsutae-test-core.XXXXXX.log); \
    if (cd Packages/TsutaeCore && swift test >"$log_file" 2>&1); then \
      echo "TEST_CORE_OK"; \
    else \
      echo "TEST_CORE_FAILED"; \
      echo "log: $log_file"; \
      tail -n 120 "$log_file"; \
      exit 1; \
    fi

# 构建 App（静默模式；失败时输出日志尾部）
build:
    @log_file=$(mktemp -t tsutae-build.XXXXXX.log); \
    if xcodebuild -project "{{xcode_project}}" -scheme "{{xcode_scheme}}" -destination 'platform=macOS' -derivedDataPath "{{derived_data}}" build >"$log_file" 2>&1; then \
      echo "BUILD_OK"; \
    else \
      echo "BUILD_FAILED"; \
      echo "log: $log_file"; \
      tail -n 120 "$log_file"; \
      exit 1; \
    fi

# 安装开发版 App 到固定路径，便于 Accessibility 权限只授权一次
install-dev: build
    @mkdir -p dist
    @rm -rf dist/Tsutae.app
    @cp -R "{{derived_data}}/Build/Products/Debug/Tsutae.app" dist/Tsutae.app
    @echo "INSTALL_DEV_OK"

# 杀掉应用
kill:
    @bash -c 'pkill -x Tsutae >/dev/null 2>&1 || true; for _ in {1..30}; do pgrep -x Tsutae >/dev/null 2>&1 || break; sleep 0.1; done; if pgrep -x Tsutae >/dev/null 2>&1; then pkill -9 -x Tsutae >/dev/null 2>&1 || true; fi'
    @echo "KILL_OK"

# 启动应用（会先杀掉旧进程，确保加载最新构建）
run: kill install-dev
    @open dist/Tsutae.app >/dev/null 2>&1
    @echo "RUN_OK"

# 不重建，只重启已安装的开发版 App。
# 用于保留 Accessibility 授权；重建后 ad-hoc 签名会变化，需要重新授权。
relaunch: kill
    @open dist/Tsutae.app >/dev/null 2>&1
    @echo "RELAUNCH_OK"

# 重启
restart: run

# 跟随 App 诊断日志。沙箱 App 写入容器内；命令行工具通常写入真实 HOME。
logs:
    @app_home="$HOME/Library/Containers/dev.yanfch.Tsutae/Data"; \
    log_dir="$app_home/.tsutae/logs"; \
    if [ ! -d "$log_dir" ]; then log_dir="$HOME/.tsutae/logs"; fi; \
    mkdir -p "$log_dir"; \
    touch "$log_dir/stt-perf.log"; \
    echo "tailing $log_dir/stt-perf.log"; \
    tail -f "$log_dir/stt-perf.log"

# 批量对比远程文本后处理模型。例：
# just remote-eval "mimo-v2.5,mimo-v2-omni"
remote-eval models="mimo-v2.5,mimo-v2-omni":
    @python3 scripts/remote_eval.py --models "{{models}}"

# 本地 rules + dictionary 转写后处理评测。
local-eval:
    @python3 scripts/local_eval.py

# 测量本地 STT 模型实际运行内存；每个模型单独子进程，默认只测已下载模型。
stt-memory-bench:
    @mkdir -p reports
    @app_home="$HOME/Library/Containers/dev.yanfch.Tsutae/Data"; \
    if [ ! -d "$app_home/Library/Application Support/FluidAudio" ]; then app_home="$HOME"; fi; \
    (cd Packages/TsutaeCore && swift build --product LocalModelMemoryBench >/dev/null && \
      HOME="$app_home" CFFIXED_USER_HOME="$app_home" \
      .build/debug/LocalModelMemoryBench --all-stt --output ../../reports/stt-model-memory.jsonl --timeout-seconds 300)
