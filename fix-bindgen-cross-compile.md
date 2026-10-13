# einat-ebpf 交叉编译 bindgen 错误修复

## 问题描述

编译 `einat-ebpf` 包时，`libbpf-sys` 的 bindgen 构建脚本报错：

```
/usr/include/bits/floatn.h:97:9: error: __float128 is not supported on this target

thread 'main' panicked at libbpf-sys-1.5.1+v1.5.1/build.rs:92:10:
Unable to generate bindings: ClangDiagnostic("/usr/include/bits/floatn.h:97:9: error: __float128 is not supported on this target\n")
```

## 根本原因

交叉编译时，`libbpf-sys` 的 bindgen 错误地使用了**主机系统**的 `/usr/include` 头文件，而非**目标平台** (aarch64-musl) 的头文件。

主机系统的 `floatn.h` 包含 `__float128` 类型定义，但该类型在 aarch64 目标平台上不受支持，导致 clang 解析失败。

## 修复方案

修改 `Makefile` 中的 `BINDGEN_EXTRA_CLANG_ARGS` 配置：

### 修改前

```makefile
CARGO_PKG_VARS+= \
	BINDGEN_EXTRA_CLANG_ARGS=-I$(shell $(TARGET_CC_NOCACHE) -print-file-name=include)
```

### 修改后

```makefile
CARGO_PKG_VARS+= \
	BINDGEN_EXTRA_CLANG_ARGS="--target=$(REAL_GNU_TARGET_NAME) --sysroot=$(TOOLCHAIN_DIR) -I$(shell $(TARGET_CC_NOCACHE) -print-file-name=include)"
```

## 参数说明

| 参数 | 作用 |
|------|------|
| `--target=$(REAL_GNU_TARGET_NAME)` | 指定目标三元组（如 `aarch64-openwrt-linux-musl`），让 clang 使用正确的目标平台配置 |
| `--sysroot=$(TOOLCHAIN_DIR)` | 指定工具链根目录，clang 会从该目录下查找系统头文件 |
| `-I$(shell $(TARGET_CC_NOCACHE) -print-file-name=include)` | 添加 GCC 内置头文件路径 |

## 验证修复

```bash
# 清理之前的构建
make package/Applications/muink/openwrt-einat-ebpf/clean V=s

# 重新编译
make package/Applications/muink/openwrt-einat-ebpf/compile V=s
```

## 相关文件

- `Makefile`: `/home/zag/OpenWrt/package/Applications/muink/openwrt-einat-ebpf/Makefile`
- 错误来源: `libbpf-sys` crate 的 `build.rs`
