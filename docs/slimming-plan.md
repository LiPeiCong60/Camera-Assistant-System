# Project Slimming Plan

This branch trims project complexity without changing user-facing behavior first.
The goal is to make the repository easier to understand, safer to publish, and
cheaper to evolve.

## Baseline

- Branch: `codex/project-slimming`
- Safe baseline commit: `f46ce49`
- Tracked files: about 291
- Largest source files:
  - `mobile_client/lib/features/device_link/device_link_page.dart`: about 6659 lines
  - `mobile_client/lib/features/camera/camera_capture_page.dart`: about 4496 lines
  - `device_runtime/api/session_manager.py`: about 1204 lines

Ignored local weight such as build outputs, virtual environments, captures,
uploads, temporary document renders, Office artifacts, and model weights should
stay outside Git.

## Principles

1. Keep behavior stable while moving code.
2. Split by responsibility, not by arbitrary line count.
3. Prefer small, reversible commits.
4. Keep generated or competition-deliverable tooling separate from runtime code.
5. Add checks before deleting or moving risky pieces.

## Phases

### Phase 1: Repository Boundaries

- Keep runtime modules at the top level: `backend`, `device_runtime`,
  `mobile_client`, `admin_web`, and `database`.
- Keep project-facing docs in `docs`.
- Move one-off document/deck/diagram generators toward `tools` after confirming
  which scripts are still useful.
- Keep maintenance scripts in `scripts`, such as cleanup, checks, and source
  statistics.
- Add a cleanup/check script after the first code split.

Acceptance:

- `git status --ignored` clearly shows local/generated artifacts as ignored.
- No Office binaries, local captures, uploads, build outputs, virtual
  environments, or model weights are staged.

### Phase 2: Mobile Device Link Split

Primary target:

- `mobile_client/lib/features/device_link/device_link_page.dart`

Planned split:

- `parts/device_link_records.dart`: local records and persistence DTOs
- `parts/ai_scan_config_dialog.dart`: AI scan parameter dialog
- `parts/device_link_widgets.dart`: shared HUD and form widgets
- `device_link_controller.dart`: polling, session lifecycle, mode changes
- `mobile_push_controller.dart`: camera stream and mobile push WebSocket
- `preview_stream_controller.dart`: preview WebSocket

Acceptance:

- The page remains behaviorally unchanged.
- The main page file falls below 3000 lines after moving low-level widgets and
  controllers.
- `flutter test` passes.

### Phase 3: Mobile Camera Page Split

Primary target:

- `mobile_client/lib/features/camera/camera_capture_page.dart`

Planned split:

- camera lifecycle
- capture and batch-pick flow
- overlay/template rendering
- AI result presentation
- gallery/history synchronization

Acceptance:

- The main camera page file falls below 2000 lines.
- Existing widget and formatter tests pass.

### Phase 4: Device Runtime Session Split

Primary target:

- `device_runtime/api/session_manager.py`

Planned split:

- session lifecycle manager
- runtime context
- status builder
- gesture capture coordinator
- AI job coordinator
- template selection coordinator

Acceptance:

- API route behavior remains unchanged.
- Session manager only owns open/current/close/list/select orchestration.
- Python tests run once `pytest` is available in the environment.

### Phase 5: Tooling And Dependency Trim

- Review `scripts` and move document/deck/diagram generators to `tools`.
- Mark WebRTC code as experimental or archive it if the NV21 WebSocket path is
  the only supported production path.
- Add `scripts/check_project.ps1` for repeatable local checks.
- Add `scripts/clean_workspace.ps1` for ignored local artifacts.

Acceptance:

- `admin_web npm run build` passes.
- `flutter test` passes.
- `git diff --check` passes.
- High-confidence secret scan has no findings.

## First Cut

Start with a low-risk split of `device_link_page.dart`:

1. Move local record/config classes into a part file.
2. Move the AI scan config dialog into a part file.
3. Run `flutter test`.
4. Continue with HUD widgets once the part-file split is proven.
