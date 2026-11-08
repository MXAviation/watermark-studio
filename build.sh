#!/bin/bash
# 批量水印工作台 / Batch Watermark Studio
# Copyright (c) 2026 KYO4926 · SPDX-License-Identifier: MIT
# 构建：编译 Swift -> 通用 Mach-O -> .app bundle -> 签名 -> 无元数据的 ZIP / DMG
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
BUILD="$HERE/.build"
DIST="$HERE/dist"
APP="$DIST/批量水印工作台.app"
EXE="WatermarkStudio"
FLAGS=(-O -swift-version 5 -parse-as-library -framework Cocoa -framework WebKit)

echo "==> 1/6 编译原生程序 (arm64 + x86_64)"
rm -rf "$BUILD"
mkdir -p "$BUILD"
swiftc "${FLAGS[@]}" -target arm64-apple-macos12.0  -o "$BUILD/arm64"   "$HERE/main.swift"
swiftc "${FLAGS[@]}" -target x86_64-apple-macos12.0 -o "$BUILD/x86_64" "$HERE/main.swift"
lipo -create "$BUILD/arm64" "$BUILD/x86_64" -output "$BUILD/$EXE"
file "$BUILD/$EXE" | head -1

echo "==> 2/6 组装 .app bundle"
mkdir -p "$DIST"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD/$EXE"                 "$APP/Contents/MacOS/$EXE"
chmod 755                        "$APP/Contents/MacOS/$EXE"
cp "$HERE/Info.plist"            "$APP/Contents/Info.plist"
cp "$HERE/app.html"              "$APP/Contents/Resources/app.html"
cp "$HERE/AppIcon.icns"          "$APP/Contents/Resources/AppIcon.icns"
find "$APP" -name '.DS_Store' -delete 2>/dev/null || true

echo "==> 3/6 Ad-hoc 代码签名"
xattr -cr "$APP" 2>/dev/null || true
codesign --force --deep --sign - "$APP"
codesign --verify --verbose=1 "$APP" 2>&1 | head -3

echo "==> 4/6 清除本机元数据（provenance / Finder 信息）"
xattr -cr "$APP" 2>/dev/null || true
STAGE="$BUILD/dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -sfn /Applications "$STAGE/Applications"
find "$STAGE" -name '.DS_Store' -delete 2>/dev/null || true
xattr -cr "$STAGE/批量水印工作台.app" 2>/dev/null || true

echo "==> 5/6 生成分发包"
rm -f "$DIST/批量水印工作台-macOS.zip" "$DIST/批量水印工作台.dmg"
# 用 Python zipfile 写入：中文文件名带 UTF-8 标记，且不含 AppleDouble / Finder 元数据
python3 - "$DIST" <<'PY'
import os, sys, zipfile
dist = sys.argv[1]
appname = "批量水印工作台.app"
app = os.path.join(dist, appname)
out = os.path.join(dist, "批量水印工作台-macOS.zip")
if os.path.exists(out):
    os.remove(out)
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    z.write(app, appname)                       # 顶层目录条目
    for root, dirs, files in os.walk(app):
        dirs[:] = sorted(d for d in dirs if not d.startswith("."))
        for name in sorted(dirs) + sorted(files):
            if name.startswith("._") or name == ".DS_Store":
                continue
            path = os.path.join(root, name)
            arc = os.path.relpath(path, os.path.dirname(app)).replace(os.sep, "/")
            z.write(path, arc)
print("ZIP: %d entries" % len(zipfile.ZipFile(out).infolist()))
PY
hdiutil create -volname "批量水印工作台" -srcfolder "$STAGE" -ov -format UDZO \
        "$DIST/批量水印工作台.dmg" >/dev/null

echo "==> 6/6 完成"
ls -lh "$APP/Contents/MacOS/$EXE" "$DIST/批量水印工作台-macOS.zip" "$DIST/批量水印工作台.dmg"
echo "APP: $APP"
