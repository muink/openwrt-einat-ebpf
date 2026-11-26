#!/bin/sh
# Workaround: bindgen generates Default for opaque structs containing
# large array padding, which fails with an older Rust toolchain (E0277).
#
# Usage: fix-libbpf-sys.sh <CARGO_HOME> <PKG_BUILD_DIR>

CARGO_HOME="$1"
PKG_BUILD_DIR="$2"
LIBBPF_SYS_GLOB="libbpf-sys-*"
found=0

# CARGO_HOME 可能同时存在 crates.io、rsproxy、USTC 等多个 registry。
# 必须全部修补，不能只取 head -1 的第一个目录。
# libbpf-sys 版本随上游升级而变化（1.5.1 -> 1.7.0），使用通配符匹配。
for build_rs in "${CARGO_HOME}"/registry/src/*/${LIBBPF_SYS_GLOB}/build.rs; do
    [ -f "${build_rs}" ] || continue
    found=1

    if grep -q 'no_default("bpf_sock")' "${build_rs}"; then
        echo "fix-libbpf-sys.sh: already patched: ${build_rs}"
        continue
    fi

    echo "fix-libbpf-sys.sh: patching ${build_rs}"

    sed -i '/\.derive_default(true)/a\
        .no_default("bpf_sock")\
        .no_default("bpf_flow_keys")' "${build_rs}" || {
        echo "fix-libbpf-sys.sh: sed failed: ${build_rs}"
        exit 1
    }
done

if [ "${found}" -eq 0 ]; then
    echo "fix-libbpf-sys.sh: no libbpf-sys found in cargo registry, skipping"
    exit 0
fi

# 若 target 已存在，删除旧 bindings 与 fingerprint，迫使 Cargo 重跑 build.rs。
if [ -d "${PKG_BUILD_DIR}/target" ]; then
    echo "fix-libbpf-sys.sh: invalidating cargo fingerprint and cached bindings.rs"

    find "${PKG_BUILD_DIR}/target" \
        -type f \
        -path '*/build/libbpf-sys-*/out/bindings.rs' \
        -delete 2>/dev/null

    find "${PKG_BUILD_DIR}/target/.fingerprint" \
        -mindepth 1 -maxdepth 1 \
        -type d -name 'libbpf-sys-*' \
        -exec rm -rf {} + 2>/dev/null
fi

exit 0
