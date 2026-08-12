# Improvements Research — Copals

This directory contains research into re-usability, modularity, and general
engineering improvements for the Copals codebase. Each document covers one
focus area, lists concrete evidence (file/line references), and proposes
changes with effort/risk estimates.

Copals is written in [Amber](https://amber-lang.com/) (`.ab`), which compiles
to Bash. The shipped artifact is the compiled `src/copals.sh`. Several findings
below are consequences of how Amber inlines imports; others are plain
source-level duplication or architecture gaps.

## Focus areas

| # | Area | File | Summary |
|---|------|------|---------|
| 1 | Compiled-output bloat | [01_compiled_output_dedup.md](01_compiled_output_dedup.md) | `copals.sh` (5884 lines) inlines every import; `_project_root` appears 48×, `resolve_vendor_dir` 27×. Proposes module extraction / build fixes. |
| 2 | Source-level DRY | [02_source_dry_consolidation.md](02_source_dry_consolidation.md) | `_project_root` copy-pasted in `vars.ab` + `vendor.ab`; vendor resolvers are 5× the same pattern; `json_config.ab` duplicates `json.ab` (self-marked TODO). |
| 3 | Modular hook/plugin system | [03_modular_hook_system.md](03_modular_hook_system.md) | generate/install/postrender hooks have inconsistent env-var contracts and no reuse mechanism; aligns with README "Future Work". |
| 4 | Testing infrastructure & coverage | [04_testing_infrastructure.md](04_testing_infrastructure.md) | Uneven coverage, no AGENTS.md test commands, parallel/lib/integration split needs hardening. |
| 5 | Cross-platform & package-manager abstraction | [05_cross_platform_abstraction.md](05_cross_platform_abstraction.md) | Debian:testing bias, sudo/doas discovery scattered, vendor resolution hardcoded paths. Aligns with README "Future Work". |
| 6 | Error handling & status propagation | [06_error_handling_consistency.md](06_error_handling_consistency.md) | Mixed `?` propagation, `failed {}`, `trust`, and `status()`; inconsistent error messages and exit codes. |

## How to read these documents

Each document follows the same structure:

1. **Problem statement** — what is wrong and why it matters.
2. **Evidence** — concrete `file:line` references from the current tree.
3. **Proposed changes** — ordered, with effort (S/M/L) and risk (Low/Med/High).
4. **Out of scope / risks** — what is deliberately not touched.

The proposals are starting points for discussion, not committed decisions.
Several overlap (e.g. 1 and 2 both touch module extraction) and should be
sequenced together where noted.
