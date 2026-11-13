# Scope review

Reviewed 2026-11-01, before implementation. A bounded search cannot establish
ecosystem uniqueness. Unindexed, unpublished or subsequently extended projects
may change this conclusion.

Searches covered Mooncakes (`moon search`), GitHub, official toolchain docs and
community repositories, using `template update`, `template scaffold`, `scaffold
sync`, `template synchronize upgrade`, `MoonBit copier`, `MoonBit cruft`, and
`template three-way`.

| Project | Inspected boundary | License / activity evidence |
|---|---|---|
| [moon-new](https://mooncakes.io/docs/moonbit-community/moon-new) | `project.create`, `template.render_repository`; absent/empty destination, Git template rendering | Apache-2.0; GitHub pushed 2026-10-19 |
| [moonctl](https://github.com/moonbitstack/moonctl) | `generate`, `generate_with`, `scaffold_api`; service generation, handler preservation; `upgrade` changes dependency pins | Apache-2.0; GitHub pushed 2026-11-01 |
| [MoonEdit](https://mooncakes.io/docs/vectie/moonedit) | `merge_three_way`, structured conflicts and accepted resolution receipts; editor core | Apache-2.0; registry 0.1.0 published 2026-08-03; subsequent repository maintenance not confirmed |

These projects cover useful lower or adjacent layers. MoonGraft owns explicit
rendered-template provenance and directory lifecycle: old baseline, current
project, new baseline, file ownership, additions/deletions, project preservation,
reviewable decisions, stale-input rejection and verified candidate export.
The current Git source reads committed files unchanged. Its creation step
overlaps with the plain Git-template case of moon-new. Its additional API
boundary is source records, planning across revisions and acceptance of a
verified candidate. Parameterized generation is planned as an adapter.

Real demand is evidenced by [Project Syn's Cruft-based component template
synchronization](https://syn.tools/syn/explanations/component_template_sync.html)
and [LinkML's Copier workflow](https://linkml.io/linkml/howtos/linkml-project-copier.html).
[Copier](https://copier.readthedocs.io/en/stable/updating/) and
[Cruft](https://github.com/cruft/cruft) are conceptual references, not ported code.
