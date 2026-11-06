#!/bin/bash
# 用 Xcode 把 iPhone6Browser 打成 .ipa。
#
#   ./build-ipa.sh
#       -> build/iPhone6Browser-unsigned.ipa
#          未签名；用 Sideloadly / AltStore / iOS App Signer 配合你的 Apple ID 重签后安装。
#
#   ./build-ipa.sh --team ABCDE12345 --bundle-id com.yourname.ip6browser
#       -> build/iPhone6Browser-signed.ipa
#          自动签名（免费 Apple ID 也能用，证书有效期 7 天；付费开发者 1 年）。
#
# 需要完整 Xcode（App Store 安装），仅装 Command Line Tools 不行。
set -euo pipefail
cd "$(dirname "$0")"

TEAM=""
BUNDLE_ID=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --team) TEAM="${2:-}"; shift 2 ;;
    --bundle-id) BUNDLE_ID="${2:-}"; shift 2 ;;
    -h|--help)
      sed -n '2,16p' "$0"
      exit 0 ;;
    *) echo "未知参数: $1"; exit 1 ;;
  esac
done

if ! xcodebuild -version >/dev/null 2>&1; then
  echo "错误：没有检测到完整 Xcode（当前是 Command Line Tools）。"
  echo "请从 Mac App Store 安装 Xcode，然后执行："
  echo "  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
  echo "  sudo xcodebuild -license accept"
  exit 1
fi

PROJECT="iPhone6Browser.xcodeproj"
TARGET="iPhone6Browser"
BUILD="$(pwd)/build"
rm -rf "$BUILD"
mkdir -p "$BUILD/Products" "$BUILD/DerivedData"

SETTINGS=("CONFIGURATION_BUILD_DIR=$BUILD/Products")
if [[ -n "$BUNDLE_ID" ]]; then
  SETTINGS+=("PRODUCT_BUNDLE_IDENTIFIER=$BUNDLE_ID")
fi

echo "==> 编译 arm64 Release (iOS 11.0+, 适配 iPhone 6 / iOS 8-12 设备)"
if [[ -n "$TEAM" ]]; then
  SETTINGS+=("DEVELOPMENT_TEAM=$TEAM" "CODE_SIGN_STYLE=Automatic")
  xcodebuild -project "$PROJECT" -target "$TARGET" \
    -configuration Release -sdk iphoneos \
    -derivedDataPath "$BUILD/DerivedData" \
    -allowProvisioningUpdates \
    "${SETTINGS[@]}" \
    build
  IPA_NAME="iPhone6Browser-signed.ipa"
else
  SETTINGS+=("CODE_SIGNING_ALLOWED=NO" "CODE_SIGNING_REQUIRED=NO")
  xcodebuild -project "$PROJECT" -target "$TARGET" \
    -configuration Release -sdk iphoneos \
    -derivedDataPath "$BUILD/DerivedData" \
    "${SETTINGS[@]}" \
    build
  IPA_NAME="iPhone6Browser-unsigned.ipa"
fi

APP_PATH="$BUILD/Products/$TARGET.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "错误：没有生成 $APP_PATH"
  exit 1
fi

mkdir -p "$BUILD/Payload"
cp -R "$APP_PATH" "$BUILD/Payload/"
(cd "$BUILD" && zip -qry "$IPA_NAME" Payload)

echo
echo "==> 完成：$BUILD/$IPA_NAME"
echo "    大小：$(du -h "$BUILD/$IPA_NAME" | cut -f1)"
echo
if [[ -n "$TEAM" ]]; then
  echo "安装方式：Xcode -> Window -> Devices and Simulators -> 选中 iPhone 6 -> '+' 添加这个 IPA；"
  echo "          或用 Apple Configurator 2 / iTunes 同步。首次打开需在 设置-通用-描述文件 里信任开发者。"
else
  echo "这是未签名 IPA，iPhone 6 不能直接装。请用以下任一方式重签："
  echo "  * Sideloadly / AltStore：拖入 IPA + 填 Apple ID，自动重签并侧载"
  echo "  * 重新运行本脚本加 --team <你的TeamID> --bundle-id <唯一ID> 直接产出已签名 IPA"
fi
echo
echo "提示：免费 Apple ID 签名有效期 7 天，到期后重新侧载即可。"
