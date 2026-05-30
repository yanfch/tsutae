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

# 杀掉应用
kill:
    -pkill -x Tsutae || true

# 启动应用
run:
    open ~/Library/Developer/Xcode/DerivedData/Tsutae-bvzzerrtrykdtkdqdxgmcmcrzltu/Build/Products/Debug/Tsutae.app

# 重启
restart: kill run
