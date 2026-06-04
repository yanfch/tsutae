# tsutae 常用命令
default:
    @just --list

# 构建 Core
build-core:
    cd Packages/TsutaeCore && swift build

# 测试 Core
test-core:
    cd Packages/TsutaeCore && swift test

# 构建 App
build:
    xcodebuild -project App/Tsutae/Tsutae.xcodeproj -scheme Tsutae -destination 'platform=macOS' build

# 安装开发版 App 到固定路径，便于 Accessibility 权限只授权一次
install-dev: build
    mkdir -p dist
    rm -rf dist/Tsutae.app
    cp -R ~/Library/Developer/Xcode/DerivedData/Tsutae-bvzzerrtrykdtkdqdxgmcmcrzltu/Build/Products/Debug/Tsutae.app dist/Tsutae.app

# 杀掉应用
kill:
    -pkill -x Tsutae || true

# 启动应用
run: install-dev
    open dist/Tsutae.app

# 不重建，只重启已安装的开发版 App。
# 用于保留 Accessibility 授权；重建后 ad-hoc 签名会变化，需要重新授权。
relaunch: kill
    open dist/Tsutae.app

# 重启
restart: kill run
