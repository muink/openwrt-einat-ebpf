#!/bin/sh
# Workaround: bindgen 0.71.1 generates Default derive for opaque structs with
# large array padding ([u8;80]/[u8;56]) which fails to compile (E0277).
# This script patches libbpf-sys build.rs after cargo fetch downloads it.
#
# Usage: fix-libbpf-sys.sh <CARGO_HOME> <PKG_BUILD_DIR>

CARGO_HOME="$1"
PKG_BUILD_DIR="$2"
LIBBPF_SYS_PKG="libbpf-sys-1.5.1+v1.5.1"

src_dir=$(ls -d "${CARGO_HOME}/registry/src/"*/"${LIBBPF_SYS_PKG}" 2>/dev/null | head -1)

if [ -z "${src_dir}" ] || [ ! -f "${src_dir}/build.rs" ]; then
    echo "fix-libbpf-sys.sh: ${LIBBPF_SYS_PKG} not found in cargo registry, skipping"
    exit 0
fi

if grep -q 'no_default("bpf_sock")' "${src_dir}/build.rs"; then
    echo "fix-libbpf-sys.sh: already patched, skipping"
    exit 0
fi

echo "fix-libbpf-sys.sh: patching ${src_dir}/build.rs"
sed -i 's/\.derive_default(true)/.derive_default(true)\n\t\t.no_default("bpf_sock")\n\t\t.no_default("bpf_flow_keys")/' \
    "${src_dir}/build.rs" || { echo "fix-libbpf-sys.sh: sed failed"; exit 1; }

echo "fix-libbpf-sys.sh: invalidating cargo fingerprint and cached bindings.rs"
find "${PKG_BUILD_DIR}/target" -name "bindings.rs" \
    -path "*/build/libbpf-sys-*/out/bindings.rs" -delete 2>/dev/null
find "${PKG_BUILD_DIR}/target" -type d -name "libbpf-sys-*" \
    -path "*/.fingerprint/*" | xargs rm -rf 2>/dev/null
exit 0
