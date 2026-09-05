# WMN Platform R3.28.5 — Custom Style Runtime Design

## Status
Approved design baseline for implementation.

## Goal
Create a centralized, metadata-driven Custom Style Runtime for WMN Platform so UI density, dimensions, typography, colors, spacing, component styling, and responsive overrides can be changed without hard-coded per-screen patches.

The runtime must style WMN Platform UI consistently across desktop, mobile portrait, mobile landscape, and constrained-height layouts while preserving the architectural boundary between Platform capabilities and managed application business logic.

## Architectural Principles

1. **Single style source** — Shell, List View, Form View, Workspace, Reports, dialogs, tables, and reusable WMN components resolve their visual tokens through the same runtime.
2. **No patch-over-patch** — existing hard-coded UI dimensions affected by this scope are replaced/consolidated rather than wrapped by additional overrides.
3. **Platform-only capability** — the runtime is generic and contains no ERP Lite business logic.
4. **Managed application independence** — managed applications may supply style metadata without requiring Flutter source changes or a host rebuild.
5. **Responsive by width and usable height** — mobile landscape and other constrained-height layouts are first-class layout states rather than being inferred from width alone.
6. **Safe fallback** — missing or invalid custom tokens fall back to the platform default style profile.

## Style Resolution Model

The effective style is resolved in this precedence order, from lowest to highest priority:

1. Platform defaults
2. Global Custom Style
3. Application Custom Style
4. Workspace/Page Custom Style
5. DocType Custom Style
6. View Custom Style (`list`, `form`, `report`, etc.)
7. Component-specific override
8. Responsive state override

The most specific valid token wins. Invalid values do not break rendering and instead fall back to the next valid level.

## Responsive States

The runtime shall expose normalized layout states:

- `desktop`
- `compact`
- `mobilePortrait`
- `mobileLandscape`
- `constrainedHeight`

A screen may match more than one raw constraint, but the resolver produces one normalized style state plus the underlying dimensions. The platform shell remains width-driven for navigation structure, while constrained-height rules can independently reduce vertical density.

## Core Runtime Components

### `WmnStyleTokens`
Immutable resolved style values used by Flutter widgets. Initial token groups:

- typography scale and key text sizes
- app bar height
- tab bar height
- toolbar height
- button height
- icon button extent
- input height
- row/list density
- field gap
- section gap
- page padding
- card padding
- border radius
- border widths
- table row/header heights
- dialog padding and maximum usable height
- sidebar widths
- component-specific compact flags

### `WmnStyleProfile`
Metadata representation of a style scope. It stores only explicitly configured overrides and scope selectors.

### `WmnStyleRuntime`
Central service responsible for:

- loading style profiles
- validating tokens
- resolving precedence
- applying responsive state overrides
- notifying listeners when effective styles change
- exposing immutable resolved tokens to UI consumers

### `WmnStyleScope`
Inherited Flutter scope or equivalent lightweight accessor that makes resolved tokens available to descendant widgets without individual database reads.

## Custom Style Metadata

A Custom Style record shall support:

- name
- enabled
- scope type
- scope target
- priority where applicable
- base/default token overrides
- responsive overrides
- optional light/dark color overrides

The storage format may use normalized columns plus JSON for token maps, but consumers never read raw JSON directly; only `WmnStyleRuntime` resolves it.

## Initial Supported Scopes

- Global
- Application
- Workspace
- Page
- DocType
- List View
- Form View
- Report
- Component

Component scope must be constrained to documented WMN component keys, not arbitrary Flutter widget traversal.

## Platform Integration

### Shell
Replace relevant hard-coded shell dimensions with resolved tokens, including:

- AppBar/compact top bar height
- sidebar widths
- navigation item density
- tab density
- toolbar button/icon sizing
- compact/constrained-height behavior

### List View
Use tokens for:

- header and toolbar density
- search/filter/sort controls
- action button sizing
- row/header heights
- page spacing

On compact layouts, secondary actions move to overflow rather than being clipped.

### Form View
Use tokens for:

- form header density
- action controls
- field/input heights
- label/text scale
- section spacing
- child table density

When embedded in Platform Shell on compact screens, avoid redundant vertical headers and preserve a single effective primary header/action region.

### Workspace / Reports / Dialogs / Tables
Adopt the same resolved tokens for common spacing, controls, rows, headers, and constrained-height behavior.

## Mobile Default Profile for R3.28.5

The platform default compact profile will target approximately:

- AppBar: 42–44 px
- Tab bar: 0–34 px depending on constrained height
- Standard buttons: 32–34 px
- Icon buttons: 32 px
- Inputs: 34–36 px
- Reduced field/section gaps
- Smaller typography scale than current mobile Platform defaults

Exact defaults are implementation constants inside the default style profile, not scattered through screen widgets.

## Managed HTML Boundary

Flutter Custom Style tokens do not pretend to be CSS. Managed HTML pages and HTML Blocks may receive a generated CSS variable set derived from safe resolved tokens, but HTML CSS remains a separate renderer concern.

No arbitrary CSS is injected into Flutter widgets.

## Error Handling

- Unknown token key: ignored and logged in diagnostics.
- Invalid numeric range: rejected with fallback.
- Invalid color value: rejected with fallback.
- Missing scope target: profile ignored.
- Duplicate scopes: deterministic precedence/priority ordering.
- Runtime failure: platform default tokens remain usable.

A malformed application style must never make the Shell unusable.

## Testing Strategy

### Unit tests
- token validation
- scope precedence
- responsive override precedence
- invalid-token fallback
- deterministic duplicate resolution

### Widget tests
- Shell reads style tokens rather than fixed affected dimensions
- compact buttons remain inside available width
- List View compact toolbar does not clip terminal actions
- Form View compact header does not duplicate the primary header region
- constrained-height tokens apply in landscape-like dimensions

### Regression tests
Existing navigation, forms, lists, workspaces, reports, theme mode, localization, and managed application routes must continue to function.

## Out of Scope for This Change

- ERP Lite POS business styling and POS performance changes; these remain ERP Lite 1.8.1 work.
- arbitrary third-party Flutter widget theming
- arbitrary CSS execution against Flutter widgets
- application business logic in Platform Core

## Expected Implementation Areas

New focused style runtime files should be added rather than placing the whole subsystem into `theme_controller.dart`.

Expected integration areas include:

- `lib/core/settings/theme_controller.dart` only where theme/color integration is required
- new `lib/platform/style/` runtime/models/validation files
- `lib/platform/ui/wmn_responsive.dart`
- `lib/platform/ui/wmn_platform_shell.dart`
- `lib/framework/ui/list/wmn_list_view.dart`
- `lib/framework/ui/form/wmn_form_view.dart`
- shared Workspace/Report/Dialog/Table components that currently own hard-coded affected density values
- runtime/bootstrap registration
- database migration/metadata seed if persistent Custom Style records require schema changes
- tests for the style runtime and compact UI behavior

## Acceptance Criteria

R3.28.5 is acceptable only when:

1. affected mobile Shell/List/Form dimensions resolve through Custom Style Runtime tokens rather than new hard-coded per-screen fixes;
2. mobile portrait and landscape no longer clip edge actions in the covered Platform views;
3. constrained-height mode reduces vertical header usage;
4. Custom Style metadata can override supported tokens without modifying the consuming screen source;
5. invalid style data safely falls back;
6. no ERP Lite business logic is added to `lib/`;
7. `flutter analyze` passes;
8. the complete Flutter test suite passes;
9. the release is documented as a clean consolidated baseline, with all modified source files listed.
