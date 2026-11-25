# MoonGraft

[![Verify](https://github.com/cn-cheems/MoonGraft/actions/workflows/ci.yml/badge.svg)](https://github.com/cn-cheems/MoonGraft/actions/workflows/ci.yml)

**面向多语言项目的模板管理与持续升级工具，也可作为 MoonBit 库集成。** 根据旧模板基线、当前项目、新模板三份文件树，生成可审阅的升级计划，保留业务修改，对重叠修改要求显式协调，再导出完整候选项目。

适合维护多个服务、库或应用模板的平台团队和开源维护者。可以直接使用本地 Git 模板，也可以接入已有生成器的渲染结果。

当前支持从本地 Git 固定提交创建或绑定项目、保存模板来源、发现本地候选版本、规划升级、导出候选并记录已采用的新版本。
可处理不同语言的普通文件，不等于兼容所有生成器或保证合并后业务语义正确。
[真实模板两个版本的完整升级证据](integration/README.md)包含来源、渲染适配、业务测试和复现命令。

状态：`0.1.0`，首个本地工作流版本；尚未发布到 Mooncakes。

初版验收入口：[复现与证据说明](docs/acceptance.md)、[变更记录](CHANGELOG.md)、
[贡献及维护流程](CONTRIBUTING.md)。当前适合评估和试用本地模板升级工作流，支持范围见下文。
[复审补充说明](docs/review-response.md)包含已实现功能、拟实现功能和 Copier、Cruft 功能对比。

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

## 从 Git 模板创建项目

先将模板仓库准备到本机。以完整的 SHA-1 提交 ID 固定版本，子目录参数用 `.` 选择根目录，
也可以使用 `templates/service` 选定一个子目录。源记录保存 Git 仓库绝对路径、子目录、提交与模板文件树。

```text
moon run cmd/main -- capture-git local-template <commit-v1> . source-v1.json
moon run cmd/main -- create-git source-v1.json generated
moon run cmd/main -- check-git source-v1.json <commit-v2>
```

新项目在 `generated/project`。Git 适配器直接读取提交中的 blob，保留文件原字节，
工作区中的未提交修改、Git 过滤器及模板钩子均不参与生成。需要本机 Git。
Git LFS 指针按提交中的原始字节保存，实际对象由使用者另行获取。来源记录绑定当前机器上的仓库路径。
Git 模板路径和文件沿用下文的边界。需要变量替换时可使用下文的参数化流程。
运行 `moon run --deny-warn scripts/git-lifecycle.mbtx` 可验证这个流程。

## 参数化模板创建与升级

在模板根目录或所选子目录提交 `moongraft.render.json`。以下声明要求两个参数，并指定 `README.md` 与原始路径 `src/@{project}.txt` 中的内容参与替换。

```json
["moongraft.render","1",[["project","title"],["README.md","src/@{project}.txt"]]]
```

在调用方保存 `parameters.json`。参数只用于构建产物，来源记录会保存明文参数。

```json
["moongraft.parameters","1",[["project","demo"],["title","团队服务"]]]
```

```text
moon run cmd/main -- capture-git-rendered local-template <commit-v1> . parameters.json source-v1.json
moon run cmd/main -- verify-git-source source-v1.json
moon run cmd/main -- create-git source-v1.json generated
moon run cmd/main -- plan-git source-v1.json generated/project <commit-v2> plan.json
moon run cmd/main -- export plan.json generated/project candidate
moon run cmd/main -- accept-git source-v1.json plan.json candidate/project source-v2.json
```

版本 1 渲染器对所有路径和显式选中的 UTF-8 文件执行一次 `@{name}` 替换，其他文件内容按原字节保留。描述文件留在模板仓库。发现未知占位符、参数不匹配、非法路径或路径碰撞时会拒绝渲染。参数值最多 128 个 UTF-16 代码单元，编码后的整组参数最多 512 个。目标提交须继续声明同一组参数。参数化来源记录固定渲染器版本、参数、Git 提交及基线。创建、规划和采用前会复核旧基线，规划及采用用同一组参数渲染目标提交。

参数化来源记录也可用于批量规划和仓库迁移。目录树 API 为 `Tree::render_parameters`。使用 `moon run --deny-warn scripts/git-lifecycle.mbtx` 可验证同一模板以两个项目名创建、分别升级两轮并保留本地改动。

## 模板参数迁移

当新版描述文件改变参数名称时，用 `plan-git-parameters` 提交显式迁移。清单中的三组规则依次是重命名、为新参数赋默认值、删除旧参数。

```json
["moongraft.parameter-migration","1",[[["project","service"]],[["tier","standard"]],["obsolete"]]]
```

```text
moon run cmd/main -- plan-git-parameters source-v1.json generated/project <commit-v2> migration.json plan.json
moon run cmd/main -- export plan.json generated/project candidate
moon run cmd/main -- accept-git source-v1.json plan.json candidate/project source-v2.json
```

规则同时作用于旧参数。未知来源、重复赋值、覆盖旧参数的默认值，以及与新版描述文件不一致的结果都会报错。迁移规则随计划保存，采用时重新渲染固定提交并核验目标基线，回退恢复旧文件树及旧基线。新来源记录可直接用于下一轮 `plan-git`。

## 模板仓库迁移

换机器或移动模板仓库后，运行 `moon run cmd/main -- relocate-git source-v2.json local-template-copy relocated-source.json`。
工具从新位置读取原记录固定的提交与子目录，逐文件核对模板基线后创建新来源记录，原位置可以已不可用。
使用新记录重新生成升级计划，再按正常流程审阅和采用。新位置对应新的模板身份，旧计划应使用其原来源记录。

## 为既有项目绑定模板

从项目历史中确认最初采用的模板提交，再创建来源记录。命令会列出既有项目相对该基线保留的本地改动，既有项目文件保持原样。
来源记录保存的是选定提交的模板快照。提交选择需要维护者确认，MoonGraft 无法从定制文件推断其来源。

```text
moon run cmd/main -- link-git local-template <original-commit-sha> . existing-project source-v1.json
moon run cmd/main -- discover-git source-v1.json
```

`discover-git` 输出 JSON，列出指向基线后代提交的本地分支、标签和本地已知的远端跟踪分支。
每条包含完整的 `ref` 和不可变的 `revision`，按引用名称排序。选择一个 `revision` 传给 `check-git` 或 `plan-git`。
命令只读取当前仓库中的 Git 引用。浅克隆中可见的历史可能不完整。需要远端更新时，先在模板仓库自行获取，再运行发现命令。

## 从记录连续升级

将下面的 `generated/project` 换成实际使用中的项目目录。归档、候选目录和来源记录均放在项目目录之外。

```text
moon run cmd/main -- plan-git source-v1.json generated/project <commit-v2> plan-v2.json
moon run cmd/main -- review plan-v2.json
moon run cmd/main -- export plan-v2.json generated/project candidate-v2
moon run cmd/main -- accept-git source-v1.json plan-v2.json candidate-v2/project source-v2.json
moon run cmd/main -- plan-git source-v2.json candidate-v2/project <commit-v3> plan-v3.json
```

若计划有冲突，先按下文方法生成已协调计划，导出及采用时都传入该计划。
先在候选目录运行自己的构建和业务测试，再采用候选并保存新记录。也可把已采用的实际项目目录传给
`accept-git`，其内容必须与计划结果一致。接受阶段核验旧基线、候选文件树及目标提交的模板文件，
然后独占创建下一版记录，旧记录可继续用于核查或回退。

## 为多个项目准备升级

在仓库根目录运行 `moon run cmd/main -- stage-git-batch batch.json output`。清单格式如下，每行依次填写项目 ID、来源记录、项目目录和目标提交 SHA。相对路径以 CLI 工作目录为准。

```json
["moongraft.git-batch.v1", [
  ["api", "api-source.json", "work/api", "<commit-sha>"],
  ["worker", "worker-source.json", "work/worker", "<commit-sha>"]
]]
```

一批支持 1–16 个项目。输出目录须是新目录，且位于各项目及模板仓库之外。每个项目独立生成计划及候选，`report.json` 按项目 ID 排序，分别标记 `ready`、`conflicts` 或 `error`。冲突项目保留可用现有命令处理的计划。批次退出码 0 表示报告成功生成，CI 可根据报告中的各项目状态设置门禁。采用候选时逐个核验，并用 `accept-git` 保存该项目的新来源记录。

批量准备完成后，可在 CI 运行 `moon run cmd/main -- check-git-batch output/report.json`。
报告中全部项目为 `ready` 时退出码为 0，存在冲突、错误或格式异常时退出失败并给出项目 ID。
这一步检查准备状态，采用前仍需核验候选目录并运行目标项目测试。

运行 `moon run cmd/main -- verify-git-batch output` 可只读核验全部为 `ready` 的批次。
它检查报告与计划的目标版本、候选与计划的逐文件一致性、基线及完成标记，并拒绝未列入报告的目录或文件。
失败时保留现场。通过后继续运行各目标项目的构建与业务测试。

新批次还保存原始 `manifest.json` 和每个已规划项目的 `source.json`，以便复核固定版本和旧模板基线。
`verify-git-batch` 会核对这些快照与报告、计划的一致性；也支持历史版本生成的无快照批次。
快照包含文件内容和本地路径，分享批次前按项目数据管理要求检查。

需要对整批应用同一套删除预算、二进制变更预算、增长预算和路径保护时，使用
`moon run cmd/main -- stage-git-batch-checked batch.json policy.json checked-output`。
策略文件与单项目 `export-checked` 相同。每个无冲突计划在创建候选前独立检查策略，
拒绝时保留计划并记录 `error`，其他项目继续准备。可调整策略后导出到新目录，
再运行 `check-git-batch checked-output/report.json` 检查状态。
库接口为 `stage_git_batch(manifest, output, policy=policy_text)`。

批次根目录的 `policy.json` 记录当时传入的公共策略或明确的空策略，逐项目策略另存于对应项目目录。
`verify-git-batch` 会使用保存的规则重新检查计划，后续修改外部策略文件也可复核原来的导出依据。
这些记录用于本地一致性核验，验收前仍应审阅实际规则。

项目需要不同规则时，使用版本 2 清单，每行增加一个必填的策略文件路径。

```json
["moongraft.git-batch.v2", [
  ["api", "api-source.json", "work/api", "<commit-sha>", "api-policy.json"],
  ["worker", "worker-source.json", "work/worker", "<commit-sha>", "worker-policy.json"]
]]
```

版本 2 也使用 `stage-git-batch`。若使用 `stage-git-batch-checked`，公共策略与逐项目策略必须同时通过。
策略文件缺失或格式异常会将对应项目标为 `error`，保留该项目的计划。
所有相对路径仍以 CLI 工作目录为准。

## 重试未完成的项目

运行 `moon run cmd/main -- retry-git-batch output/manifest.json output/report.json retry.json`，
可以提取状态为 `conflicts` 或 `error` 的项目，保留其来源路径、项目路径、目标提交和逐项目策略配置。
工具先检查报告与原清单的项目 ID 及目标版本对应。全部就绪时只输出提示，不创建空清单。
修复输入或协调项目后，将 `retry.json` 交给 `stage-git-batch`，输出到新的目录。
原批次使用公共策略时，重试仍须通过 `stage-git-batch-checked` 显式传入公共策略。
相对路径仍以当前工作目录解释；重试清单保留原来的路径文本。

## 整批验收

在各候选目录运行项目自身的构建和业务测试后，执行
`moon run cmd/main -- accept-git-batch output accepted-sources`。
它先核验整批候选及保存的策略，再使用批次内的来源快照逐项核对 Git 目标提交。
全部通过后，才创建新目录并写入每个项目的新来源记录（如 `api.json`），最后写入 `acceptance.json`。
记录文件以报告中的 `projects[].source` 为准。项目 ID 为 `acceptance` 时，来源记录写入 `acceptance.source.json`。
采用对应候选时保存其新来源记录，下一轮升级使用该记录。
外部来源文件的后续编辑不会改变本次验收依据。验收需要本地模板仓库可访问，迁移后先按迁移流程重新准备批次。
写入失败时保留已写记录，完成标记未生成的目录应保留检查，并改用新目录重新验收。
历史无来源快照的批次可继续逐项目验收，整批验收需重新准备带快照的批次。

## 模板文件重命名

上游移动模板文件时，用版本化映射明确声明旧路径和新路径。

```json
["moongraft.renames","1",[["ci/build.yml",".github/workflows/build.yml"]]]
```

```text
moon run cmd/main -- plan-git-renames source.json my-project <target-sha> renames.json plan.json
moon run cmd/main -- plan-renames baseline.json my-project v2 template-v2 renames.json plan.json
```

工具按新路径合并旧模板、本地文件和新模板。显式映射适用于一对一文件移动，要求旧路径只存在于旧模板，新路径只存在于新模板。目标已被本地文件占用或存在文件与目录碰撞时，规划会报告错误，维护者可先处理冲突路径。若本地已删除旧文件，计划会要求决定是否保持删除。

审阅和决策使用新路径。`keep-local` 将原文件的本地版本写到新路径，原文件已删除时保留该删除。预算和路径保护按候选的实际新增、删除和修改检查移动。刷新保留映射，回退会恢复原文件树与原基线。含移动的 JSON 审阅报告使用版本 2。
运行 `moon run --deny-warn scripts/git-lifecycle.mbtx` 可验证固定提交的移动、采用和回退。

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

推荐 CI 使用 `export-checked resolved.json my-project policy.json candidate`，让快照检查、
变更预算与路径保护全部通过后才创建导出目录。策略格式为
`["moongraft.policy","1",[最多删除数,最多二进制变更数,最大净增长字节数,[保护路径]]]`，
可参考 [示例策略](examples/service/policy.json)。库接口为 `Plan::prepare`。
普通 `export` 保持原行为，不隐式加载策略；这两种模式均不会替换源项目。

路径保护：`protect resolved.json protected.json` 接受严格格式
`["moongraft.protected","1",["src/","config/production.json"]]`。
目录规则以 `/` 结尾，文件规则按完整路径匹配；ASCII 大小写不敏感，不解释 glob。
规则针对实际输出，新增、删除、内容和可执行属性变化均可被阻止，包括目录被同名文件替代。
库接口为 `Plan::check_protected` / `check_protected_json`；这是显式门禁，导出前须自行调用。

保守刷新：`refresh old-plan.json my-project new-plan.json` / `Plan::refresh(current)`
吸收新的项目快照；仅当某冲突的基线、本地、模板版本及原因完全相同时保留既有决策。
发生内容或属性变化、已收敛的冲突都会撤销旧决策，并列出 retained/dropped 路径。
刷新产生新计划，旧计划不变；旧批量审阅文件不能跨计划复用。

过期定位：`drift-json plan.json my-project` / `Plan::project_drift(current)` 返回新增、
删除及内容/可执行属性变化的路径，便于理解旧计划为何被拒绝；它不会修改或刷新计划，
报告不包含文件内容，顺序固定为路径字典序。

回退候选：`rollback-export resolved.json candidate/project rollback-candidate` 将完整旧项目和
旧模板基线写入新目录；库接口是 `Plan::rollback(candidate)`。候选必须与计划的升级输出
完全一致，新增文件、内容或属性修改都导致拒绝，防止覆盖升级后的新工作。
此操作不会自动替换工作目录。`scripts/demo.mbtx` 同时演示预览、门禁和可验证回退。

升级门禁：`gate resolved.json 0 0 1048576` 要求实际输出不删除文件、不改变二进制文件，
内容净增长最多 1 MiB。库接口为 `Plan::check_policy`；超限聚合返回 `PolicyRejected`，
CLI 非零退出。门禁覆盖人工替换结果，但不会隐式成为导出前置条件；CI 应显式先运行 gate。

结果预览：`preview-json resolved.json` / `Plan::output_changes()` 列出相对当前项目的
实际新增、删除、内容或可执行属性变化。它与合并来源报告不同：选择保留本地的冲突不会
被误计为文件修改。预览要求全部冲突已解决，输出按路径排序，不包含文件内容。

只读验收：`verify-export candidate`（库接口 `workspace.verify_export`）校验完成标记、
基线、目录结构和全部文件字节，不创建、删除或修复任何文件。适合 CI 检查已审阅候选包；
缺失文件或陌生数据均失败，需要恢复时再显式运行 `resume`。

CI 集成可调用 `report-json plan.json` 或 `Plan::report_json()`。
普通计划输出 `["moongraft.report","1",模板标识,旧版本,新版本,变更行,未解决路径]`。
含移动的报告使用版本 `"2"`，最后一项追加 `[[旧路径,新路径], ...]`。
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

独立采用验证：`moon run scripts/package-check.mbtx --portable-only` 从本地 ZIP 包创建临时工作区，
运行[独立消费者](examples/consumer/README.md)。不依赖未发布的 Mooncakes 包，依赖安装仍可能访问公共注册表。

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

长文本的完整差分超过预算时，MoonGraft 分别裁剪旧模板与本地版本、旧模板与新版之间相同的前后行，再在每个变更区间内计算差分。变更位置仍以旧模板为基准。每个差分表最多 262,144 个单元，扫描的行数上限保持 4,096。跨度过大的修改仍报告 `conflict:text-merge-limit`，可通过审阅明确选择结果。
新规划的归档使用版本 3。版本 1 和 2 归档继续按原差分规则重放，保留已有审阅决策。重新规划可使用新的长文本差分规则。

## 差异化与后续方向

这是参考 [Copier](https://github.com/copier-org/copier) 和 [Cruft](https://github.com/cruft/cruft) 工作流的新 MoonBit 实现。现有 [moon-new](https://github.com/moonbit-community/moon-new) 负责创建项目，[moonctl](https://github.com/moonbitstack/moonctl) 侧重服务代码生成，[MoonEdit](https://mooncakes.io/docs/vectie/moonedit) 提供编辑器与文本合并核心。MoonGraft 的边界是模板来源、目录级三方升级、审阅决策、连续版本基线和完整候选项目导出。[调研依据与不确定性](docs/ecosystem.md)。

计划中的能力包括条件渲染、外部生成器适配和远程 Git 版本发现。

## 许可证与来源

Apache-2.0。源码、测试与示例的复用范围见 [THIRD_PARTY.md](THIRD_PARTY.md)。不宣称生态唯一、格式全面兼容或未经测量的性能优势。
