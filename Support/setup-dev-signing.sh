#!/usr/bin/env bash
# 创建本地自签名代码签名身份 "MoniSwitch Dev"（一次性）。
#
# 背景（2026-10-17 实锤）：App 用 ad-hoc 签名时，TCC（输入监控/辅助功能）把
# cdhash 写进授权记录；每次重新打包 cdhash 必变，授权随即失效。换成固定的
# 自签名证书后，TCC 的 code requirement 只含 identifier + 证书指纹，重新打包
# 授权不丢（系统设置里的开关不会再「亮着但没生效」）。
#
# 用法：bash Support/setup-dev-signing.sh
# 幂等：身份已存在则直接返回。
set -euo pipefail

IDENTITY_NAME="${1:-MoniSwitch Dev}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning 2>/dev/null | grep -qF "\"${IDENTITY_NAME}\""; then
    echo "✓ 签名身份已存在: ${IDENTITY_NAME}"
    security find-identity -v -p codesigning | grep -F "${IDENTITY_NAME}"
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT
cd "${TMP}"

# 自签证书：CN = 身份名，带 codeSigning 扩展（codesign 只认这个 EKU）。
openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
    -subj "/CN=${IDENTITY_NAME}" \
    -addext "basicConstraints=critical,CA:false" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" \
    -keyout key.pem -out cert.pem >/dev/null 2>&1

# macOS Security 对 OpenSSL 3 默认 PKCS#12 算法不兼容时退回 -legacy；
# 系统自带的 LibreSSL 不支持该选项，所以两条路都试。
if ! openssl pkcs12 -export -legacy -inkey key.pem -in cert.pem \
        -out identity.p12 -passout pass:moniswitch >/dev/null 2>&1; then
    openssl pkcs12 -export -inkey key.pem -in cert.pem \
        -out identity.p12 -passout pass:moniswitch >/dev/null 2>&1
fi

# -T 把 codesign 加入私钥 ACL，避免每次签名弹「允许访问钥匙串」。
security import identity.p12 -k "${KEYCHAIN}" -P moniswitch \
    -T /usr/bin/codesign -T /usr/bin/security >/dev/null

# 信任为代码签名根（用户 trust domain，无需 sudo）。
security add-trusted-cert -r trustRoot -k "${KEYCHAIN}" cert.pem

echo "✓ 已创建签名身份:"
security find-identity -v -p codesigning | grep -F "${IDENTITY_NAME}"
