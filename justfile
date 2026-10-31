# 开发命令入口（README §快速开始 / §开发）；前提：fvm 已安装且已 fvm install

dev-app:
    fvm flutter run -d macos

dev-services:
    fvm dart run services/mangasvc/bin/mangasvc.dart --engine mock &
    fvm dart run services/animesvc/bin/animesvc.dart &
    wait

test:
    fvm flutter test

# 服务端单测（纯 Dart，不需要 Flutter）
test-svc:
    fvm dart test services/mangasvc

# 端到端：起 mock 服务后跑 e2e（否则 e2e 会显式跳过）
test-e2e:
    fvm dart run services/mangasvc/bin/mangasvc.dart --engine mock --root /tmp/miaodock-e2e &
    sleep 8
    fvm flutter test
    kill %1

analyze:
    fvm flutter analyze

format:
    fvm dart format .

# 生成国际化词条（D-006）
l10n:
    fvm flutter gen-l10n

# 中文硬编码棘轮检查（D-006）
check-l10n:
    fvm dart run tool/check_l10n.dart
