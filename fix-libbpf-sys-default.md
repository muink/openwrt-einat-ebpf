# Fix: libbpf-sys 1.5.1 bindgen Default derive compile error

## 错误现象

编译 `einat-ebpf` 时报错：

```
error[E0277]: the trait bound `[u8; 80]: Default` is not satisfied
error[E0277]: the trait bound `[u8; 56]: Default` is not satisfied
```

涉及结构体：`bpf_sock`（`[u8; 80]` padding）和 `bpf_flow_keys`（`[u8; 56]` padding）。

## 根本原因

`libbpf-sys 1.5.1` 的 `build.rs` 中 `.derive_default(true)` 让 `bindgen 0.71.1` 对所有结构体派生 `Default`，但它未正确处理大数组 padding 的可实现性，导致编译失败：

```rust
// bindgen 生成的 bindings.rs（有问题）
#[repr(C)]
#[derive(Debug, Default, Copy, Clone)]   // ← Default 派生触发 E0277
pub struct bpf_sock {
    pub __bindgen_padding_0: [u8; 80usize],  // ← 大数组 padding
    pub _address: u8,
}
```

**注意**：与 Rust 版本无关（Rust 1.47+ 已支持大数组 Default）。问题在于 `libbpf-sys` 使用 `edition = "2018"`，而 bindgen 0.71.1 生成的代码未正确声明所需 feature。

## 修复方案

在 `build.rs` 的 `bindgen::Builder` 链上，对两个问题结构体禁用 `Default` 派生：

```diff
     bindgen::Builder::default()
         .derive_default(true)
+        .no_default("bpf_sock")
+        .no_default("bpf_flow_keys")
         .explicit_padding(true)
```

## 实现方式

### 为什么不能直接 patch CARGO_HOME/registry/src/

cargo 的 `registry/src/` 是全局缓存，有两个致命问题：

1. **全新环境**：`cargo fetch` 之前文件不存在，patch 时机无法保证
2. **增量编译**：cargo 不追踪 `registry/src/` 文件变化，patch 后不会重新运行 build script，旧的 `bindings.rs` 缓存仍被使用

### 为什么不能在 Makefile 内联 shell

Makefile 不理解 shell 引号，`grep -q 'no_default("bpf_sock")'` 中的 `(` 会被 make 当作函数调用解析，导致命令错误。另外 `$$varname` 在 make 中展开为 `$varname`，make 再次展开 `$v` 为 make 变量（通常为空），导致变量名被截断（如 `$src_dir` → `rc_dir`）。

### 正确流程

```
cargo fetch  →  fix-libbpf-sys.sh（patch build.rs + 删除旧缓存）  →  cargo install
```

1. `cargo fetch --locked`：将所有依赖下载解压到 `CARGO_HOME/registry/src/`
2. `fix-libbpf-sys.sh`：patch `build.rs`，并删除 cargo fingerprint 目录和缓存的 `bindings.rs`，强制 build script 重新运行
3. `cargo install`：重新生成正确的 `bindings.rs` 并完成编译

## 文件清单

| 文件 | 说明 |
|------|------|
| `fix-libbpf-sys.sh` | 执行 patch 的 shell 脚本，幂等（已 patch 则跳过） |
| `Makefile` | `Build/Compile` hook：fetch → fix → compile |

### Makefile 关键片段

```makefile
# Workaround: bindgen 0.71.1 generates Default derive for opaque structs with
# large array padding ([u8;80]/[u8;56]) which fails to compile (E0277).
# Fix: cargo fetch downloads libbpf-sys first, then fix-libbpf-sys.sh patches
# build.rs and invalidates the cargo fingerprint so bindings.rs is regenerated.
define Build/Compile
	+$(CARGO_PKG_VARS) \
		cargo fetch \
		--manifest-path "$(PKG_BUILD_DIR)/Cargo.toml" \
		--locked
	$(CURDIR)/fix-libbpf-sys.sh "$(CARGO_HOME)" "$(PKG_BUILD_DIR)"
	$(call Build/Compile/Cargo)
endef
```

### fix-libbpf-sys.sh 逻辑

1. 在 `CARGO_HOME/registry/src/*/libbpf-sys-1.5.1+v1.5.1/` 定位 `build.rs`
2. 检测是否已 patch（幂等保护）
3. `sed` 注入 `.no_default("bpf_sock").no_default("bpf_flow_keys")`
4. 删除 `PKG_BUILD_DIR/target` 内的 libbpf-sys fingerprint 目录和 `bindings.rs`，触发重新生成

## 受影响版本

| 组件 | 版本 |
|------|------|
| `einat-ebpf` | 0.1.10 |
| `libbpf-sys` | 1.5.1+v1.5.1 |
| `bindgen` | 0.71.1 |
| Rust | 1.95.0（不影响，问题在 bindgen） |

## 上游状态

此为 bindgen 0.71.x 的已知问题。升级 `libbpf-sys` 到修复版本后，可删除 `fix-libbpf-sys.sh` 并恢复 `Build/Compile` 为默认的 `$(call Build/Compile/Cargo)`。
