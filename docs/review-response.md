# MoonGraft｜MoonBit 黑客松项目申报书（复审版）

**1. 项目名称**　MoonGraft：通用项目模板管理与持续升级工具。

**2. 项目简介**　平台团队维护多个派生仓库时，常需反复同步模板的 CI、构建配置与目录结构。MoonGraft 串起项目创建或绑定、版本发现、升级规划、冲突处理、候选验证和基线推进，让维护者保留各仓库的业务改动，并持续采用新版模板。

**3. 项目方向与通用性**　面向平台团队、脚手架维护者和开源项目的开发者工具，提供 MoonBit 库及 CLI。基于可移植文件树、Git 提交和版本化记录，适用于不同语言的服务、应用与库。可从本地 Git 模板创建项目，也可接入已有生成器的渲染目录。

**4. 预期使用场景**

1. **新服务持续升级。** 从固定模板提交创建服务。上游更新 CI 后，生成升级候选，核对自定义检查仍在，运行服务测试并记录新基线。
2. **既有仓库接入。** 将已定制的开源库绑定到历史模板提交，发现新标签并生成计划。维护者解决 README 冲突，通过发布前测试后采用候选，并保存新来源记录。
3. **批量同步多个仓库。** 为 API、Worker 等项目准备各自的目标版本，批量输出候选和 JSON 状态。先验收无冲突项目，逐项处理其余冲突，各自推进基线。

**5. 核心功能与验收**

- **已实现**　固定提交创建或绑定、发现本地候选版本、三方升级与显式冲突处理、候选导出和回退、验收后推进基线，以及最多 16 个项目的本地批量准备。导出前检查当前快照，验收时核对候选文件与目标模板记录。
- **拟实现**　固定生成器版本并记录非敏感参数，用两组参数复现生成及后续升级。增加显式远程版本获取，用上游更新验证可发现、固定并复用同一目标提交。
- **复现**　运行 `moon run --deny-warn scripts/git-lifecycle.mbtx`，可验证两轮升级及同批项目的成功、冲突、错误隔离。另有公开模板历史版本的构建和回归测试案例。 [公开模板案例](../integration/README.md)

**6–7. 实现来源与成熟工具对比**　MoonBit 独立实现，采用 Apache-2.0。产品流程参考 Copier 与 Cruft，无移植项目。Copier 采用 Jinja 与回答文件，Cruft 基于 Cookiecutter 并提供 `link`、`check`、`diff`。MoonGraft 现有能力侧重固定提交的来源记录、独立候选、显式验收和逐项目批量状态。MoonBit 生态的 `moon-new` 已提供项目生成，可通过其渲染输出接入目录升级流程。 [Copier](https://copier.readthedocs.io/en/stable/updating/) · [Cruft](https://cruft.github.io/cruft/) · [moon-new](https://mooncakes.io/docs/moonbit-community/moon-new)

**8. GitHub 仓库**　主分支已有超过 10 个涉及实现、测试或验收的有效提交。 [仓库](https://github.com/cn-cheems/MoonGraft) · [提交记录](https://github.com/cn-cheems/MoonGraft/commits/main/) · [跨平台 CI](https://github.com/cn-cheems/MoonGraft/actions/workflows/ci.yml)
