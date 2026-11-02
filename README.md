# MoonGraft

[![Verify](https://github.com/cn-cheems/MoonGraft/actions/workflows/ci.yml/badge.svg)](https://github.com/cn-cheems/MoonGraft/actions/workflows/ci.yml)

**项目模板持续升级工具与 MoonBit 库。** 根据旧模板基线、当前项目、新模板三份文件树，生成可审阅的升级计划，保留业务修改，对重叠修改要求显式协调，再导出完整候选项目。

适合维护多个服务、库或应用模板的平台团队和开源维护者。已有模板生成器可以继续生成文件；MoonGraft 接收其渲染结果，负责项目创建之后的升级生命周期。

状态：`0.1.0`，首个本地工作流版本；尚未发布到 Mooncakes。

## 快速验证

使用 MoonBit `0.10.17+d971670cd`。项目采用当前工具链识别的 `moon.mod` / `moon.pkg`；命令在仓库根目录执行。

```text
git clone https://github.com/cn-cheems/MoonGraft.git
cd MoonGraft
moon update
moon run --deny-warn scripts/demo.mbtx
```

演示以社区真实模板中的 CI 文件为输入，合并团队自定义检查与模板工具链版本更新，人工协调 README，验证业务文件保留、模板增删、下一版本基线，以及独立进程恢复。它会输出临时目录供检查，无需账号、API 密钥或私有设施。[输入来源和修改说明](examples/service/SOURCES.md)。

完整便携目标检查：

```text
moon run --deny-warn scripts/verify.mbtx --portable-only
```

完整检查（含原生测试和原生 CLI 实际运行，需要本机 C 工具链；Windows 需要 MSVC C++ Build Tools 与 Windows SDK）：

```text
moon run --deny-warn scripts/verify.mbtx
```

## 实际目录升级

`template-v1` 和 `template-v2` 是使用相应版本与项目变量渲染好的模板目录。基线、计划与导出目录放在当前项目之外。输出文件使用独占创建，重复执行时请换一个新名称。

```text
moon run cmd/main -- track team/service v1 template-v1 baseline.json
moon run cmd/main -- plan baseline.json my-project v2 template-v2 plan.json
moon run cmd/main -- review plan.json
moon run cmd/main -- show plan.json README.md
moon run cmd/main -- replace plan.json README.md reviewed-readme.md resolved.json
moon run cmd/main -- export resolved.json my-project candidate
```

也可以用 `resolve <plan> <path> keep-local|take-template|delete <new-plan>` 选择某一方或删除。每次协调产生新计划，支持分次审阅。`replace` 读取人工协调后的实际文件及其可执行属性。

成功导出包含：

```text
candidate/
  intent.json      # 完整预期内容与基线，用于核验和恢复
  project/         # 完整候选文件树
  baseline.json    # 下一次升级使用的新模板基线
  complete.json    # 逐文件核验成功后才生成
```

运行 `git diff --no-index my-project candidate/project` 审阅文件差异，并运行项目自己的构建和测试。该 diff 命令发现差异时退出码为 1。采用候选内容时，必须同时保存 `candidate/baseline.json`；它记录的是新模板，而非混入业务修改的候选目录。工具不会操作 Git 或自动替换原项目。

导出中断后运行 `moon run cmd/main -- resume candidate`。恢复会重新核验已写文件，只接受与预期内容一致的文件；保留人工修改和陌生数据并报错。带有效待写记录的保留区临时文件，只有内容属于预期文件的字节前缀时才清理重写。意图记录本身写入中断或损坏时会拒绝恢复，应保留现场并导出到新目录。完成标记是一次验证记录；之后修改了目录，仍应重新执行 `resume` 验证。

## 已实现的规则

只读验收：`verify-export candidate`（库接口 `workspace.verify_export`）校验完成标记、
基线、目录结构和全部文件字节，不创建、删除或修复任何文件。适合 CI 检查已审阅候选包；
缺失文件或陌生数据均失败，需要恢复时再显式运行 `resume`。

CI 集成可调用 `report-json plan.json` 或 `Plan::report_json()`。
输出固定结构 `["moongraft.report","1",模板标识,旧版本,新版本,变更行,未解决路径]`；
每行包含路径、分类和决策（未决策为 null），按路径排序，适合解析归档。

批量审阅：`review-template plan.json review.json` 创建绑定当前计划的空审阅文件。
在外层 payload 的第二项数组中填写决策，例如 `["README.md", ["keep-local"]]`。
执行 `apply-review plan.json review.json resolved.json` 原子应用整批决策。
保留第一项中的完整计划字符串；计划或已有决策发生变化后，旧审阅文件会被拒绝。

- 模板未改时保留项目内容；项目未改时采用模板内容；双方相同修改自动收敛。
- 项目独有文件保留；上游新增同名文件时报告冲突。
- UTF-8 文本按保留行结束符的行序列进行保守三方合并；重叠修改需要决策。
- 保留 BOM、CRLF、末尾换行状态、任意二进制字节和核心模型中的可执行属性。
- 删除/修改、修改/删除、双方新增、双方修改、文本合并预算超限都有明确分类。
- 未解决冲突、重复或无效决策、过期项目快照、大小写或文件/目录碰撞均拒绝应用。
- 树、基线和计划采用确定性的版本化 JSON 数组格式；拒绝未知标签、额外字段和未知版本。文件内容用小写 hex 保存；解码计划重新执行规划与决策校验。
- 所有核心操作返回新值；失败后原输入和已有计划仍可使用。

公开 API 见 [生成接口](pkg.generated.mbti)、[可运行库示例](README.mbt.md) 和 [设计约定](docs/design.md)。核心包不依赖主机 I/O；`workspace` 包提供文件系统适配，`cmd/main` 提供 CLI。

## 支持范围

| 项目 | 范围 |
|---|---|
| 核心库 | Wasm、Wasm-GC、JavaScript、原生目标 |
| 文件系统与 CLI | Wasm、原生；目标操作系统为 Windows、Linux、macOS，由 CI 分别验证 |
| 路径 | 1–240 字符的可移植 ASCII 相对路径，使用 `/`；拒绝遍历、设备名、大小写碰撞等 |
| 文件内容 | 任意字节；合法 UTF-8 且无 NUL 时才尝试文本合并 |
| 资源上限 | 每树 2048 文件、每文件 2 MiB、每树 16 MiB；替换决策总内容 16 MiB |
| 文本合并 | 最多约 4096 行，每次 LCS 表最多 262144 单元；超限作为显式冲突 |
| 权限 | 核心保留可执行布尔属性；POSIX 输出规范化为 0644/0755；Windows 不表示 POSIX 执行位 |

扫描仅明确排除根目录 `.git` 元数据。隐藏文件和 `.gitignore` 中的文件均会扫描；不会悄悄忽略构建产物。空目录、符号链接、特殊文件、非支持路径与超限输入均报错拒绝。

当前不支持模板脚本执行、远程模板获取、自动重命名识别、Jinja/Cookiecutter 兼容、JSON/YAML 语义合并、原地更新、所有权/ACL/其他权限位保留、并发写入或断电持久性保证。目录扫描和导出要求调用者提供可信且独占使用的本地目录。

## 差异化与后续方向

这是参考 [Copier](https://github.com/copier-org/copier) 和 [Cruft](https://github.com/cruft/cruft) 工作流的新 MoonBit 实现。现有 [moon-new](https://github.com/moonbit-community/moon-new) 负责创建项目，[moonctl](https://github.com/moonbitstack/moonctl) 侧重服务代码生成，[MoonEdit](https://mooncakes.io/docs/vectie/moonedit) 提供编辑器与文本合并核心。MoonGraft 的边界是模板来源、目录级三方升级、审阅决策、连续版本基线和完整候选项目导出。[调研依据与不确定性](docs/ecosystem.md)。

计划中的能力：显式重命名映射、现有生成器适配、固定 Git 版本获取、多仓库批量升级。它们尚未实现。

## 许可证与来源

Apache-2.0。源码、测试与示例的复用范围见 [THIRD_PARTY.md](THIRD_PARTY.md)。不宣称生态唯一、格式全面兼容或未经测量的性能优势。
