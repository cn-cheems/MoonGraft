# Sources and licenses

- MoonGraft source, tests and scenario files: authored for this repository,
  Apache-2.0. No Copier, Cruft or MoonEdit implementation or test suite is copied.
- Workflow reference: [Copier](https://github.com/copier-org/copier), MIT;
  [Cruft](https://github.com/cruft/cruft), MIT. They validate the user problem;
  their CLI formats and template syntax are not claimed compatible.
- Runtime dependency: [moonbitlang/async](https://github.com/moonbitlang/async),
  version 0.22.5, Apache-2.0; filesystem and subprocess adapters only. The standard
  library is supplied by the MoonBit toolchain (Apache-2.0).
- Public workflow fixture: the exact source revision, Apache-2.0 license and
  disclosed local derivatives are recorded in [examples/service/SOURCES.md](examples/service/SOURCES.md).
  The upstream file's comments and bytes are retained in the v1 fixture.
- LCS dynamic programming and three-way interval composition are implemented in
  MoonGraft; this is a standard algorithmic approach, not a claimed invention.
- CI invokes `actions/checkout`, `actions/setup-node` (MIT),
  `ilammy/msvc-dev-cmd` (MIT), and `hustcer/setup-moonbit` (MIT). Their source is
  not redistributed in this repository. Each action retains its own license.
- The root LICENSE is the standard Apache License 2.0 text from
  https://www.apache.org/licenses/LICENSE-2.0.txt.

No generated interfaces are hand-edited. The repository does not contain a
Python, JavaScript or shell implementation of the upgrade engine.

The archive-consumer verification approach was informed by the Apache-2.0
[BIDS-Metadata-Trace package workflow](https://github.com/cn-cheems/BIDS-Metadata-Trace).
MoonGraft's script and consumer are authored here; no BIDS domain logic is used.

- Complete historical template snapshots: `mizchi/moonbit-template`, Apache-2.0,
  commits and disclosed adaptations documented in [integration/README.md](integration/README.md).
  Each snapshot includes upstream LICENSE, source, tests and notices verbatim.
  The example project adds clearly marked local business files and README text.
- The case uses `moonbitlang/quickcheck@0.15.1` (Apache-2.0) as an explicit
  compatibility pin for the upstream property's test dependency. It is not a
  dependency of the MoonGraft core.
