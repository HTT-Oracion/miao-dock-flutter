# 开发命令入口（README §快速开始 / §开发）；前提：fvm 已安装且已 fvm install

dev-app:
    fvm flutter run -d macos

dev-services:
    fvm dart run services/mangasvc/bin/mangasvc.dart --engine mock &
    fvm dart run services/animesvc/bin/animesvc.dart &
    wait

test:
    fvm flutter test

analyze:
    fvm flutter analyze

format:
    fvm dart format .
