# tsutae 常用命令
set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

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
    if xcodebuild -project App/Tsutae/Tsutae.xcodeproj -scheme Tsutae -destination 'platform=macOS' build >"$log_file" 2>&1; then \
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
    @cp -R ~/Library/Developer/Xcode/DerivedData/Tsutae-bvzzerrtrykdtkdqdxgmcmcrzltu/Build/Products/Debug/Tsutae.app dist/Tsutae.app
    @echo "INSTALL_DEV_OK"

# 杀掉应用
kill:
    @pkill -x Tsutae >/dev/null 2>&1 || true
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

# 批量对比远程文本后处理模型。例：
# just remote-eval "mimo-v2.5,mimo-v2-omni"
remote-eval models="mimo-v2.5,mimo-v2-omni":
    @python3 scripts/remote_eval.py --models "{{models}}"

# 本地 rules + dictionary 转写后处理评测。
local-eval:
    @python3 scripts/local_eval.py
