# herdr-ordo

A [herdr](https://herdr.dev) plugin that opens [ordo](https://github.com/FoamScience/ordo)
in a tab of its own, named `ordo`, next to your agent's. You read the agent's
diff in ordo's reading order, note and comment on it, and `:send` the review
back to the agent as typed input.

- **Review tab**: ordo on the repository you opened it from, with the whole
  screen to itself (or split beside the chat, with `PLACEMENT=split`).
- **Send to the agent**: ordo's `:send` types the review into the workspace's
  agent without pressing Enter, and focuses it, so you read it over and submit.
- **Follows the agent**: the review marks itself stale as the agent keeps
  editing, and `r` reads it again without losing your place (`WATCH=auto`
  reloads by itself when you pause).
- **Waves**, opt in with `WAVES=1`: each agent turn is recorded as a wave
  (`ordo wave`), so `:e wave/2..wave/3` reviews one turn and
  `:e wave/0..wave/last` everything since the review opened.
- **Auto-open**, opt in with `AUTO_OPEN=1`: a new worktree workspace gets a
  review tab, without taking focus from the agent.

The plugin runs ordo and herdr's own CLI. It never edits the worktree; with
`WAVES=1` it adds refs under `refs/worktree/ordo/waves/`, and `ordo wave --clear`
removes them.

## Requirements

- herdr ≥ 0.7.5
- `ordo` itself, recent enough to know `--watch`, installed separately, for
  example `cargo install --path <ordo checkout>`
- `git`, `jq`, `bash`

## Install

From a checkout:

```bash
herdr plugin link ~/repo/herdr-ordo
herdr plugin action invoke foamscience.ordo.toggle
```

Bind the toggle to a key in herdr's `config.toml`:

```toml
[[keys.command]]
key = "prefix+o"
type = "plugin_action"
command = "foamscience.ordo.toggle"
description = "ordo review tab"
```

The toggle opens the `ordo` tab, focused, or closes it when it is open. From
the tab, herdr's own tab keys take you back to the agent and in again; `open`
brings an open review tab to the front instead of opening a second one. Close
it by hand and the next toggle opens a fresh one.

## In the tab

It is ordo, so everything ordo does applies. For the review loop:

| key / command | does |
| --- | --- |
| `:note <text>` | a note on the selected hunk's symbol |
| `v`, then `c` | select lines in the code pane and comment on them |
| `gc` / `gC` | next / previous comment |
| `:send` | type the review into the agent, notes and comments, anchored `path:line` |
| `:send all` | the same, with ordo's own findings added |
| `:yank` | copy the review to the clipboard instead |
| `r` | read the change again after the agent edited, keeping your place |
| `:watch auto` | reload by itself from now on |

Which agent receives it:
- `AGENT_PANE`, when set.
- Otherwise the agent you opened the review from.
- Otherwise the only agent in the workspace.
- Otherwise the only agent in the review's own tab (with `PLACEMENT=split`, the chat's).

With several candidates and no way to tell them apart, `:send` refuses and
names them.

## Configuration

`$(herdr plugin config-dir foamscience.ordo)/config.env` is a plain shell file
of `KEY=value` lines. Quote any value with spaces.

| key | default | meaning |
| --- | --- | --- |
| `ORDO_BIN` | `ordo` | the ordo binary |
| `ORDO_ARGS` | `zz` | what to review: `zz` is the uncommitted work; `"main...zz"` is everything since the branch left `main`, uncommitted included |
| `WATCH` | `hint` | `hint`: mark the review stale when the agent edits, `r` reloads; `auto`: reload by itself when you pause; `off` |
| `WAVES` | `0` | `1` records a wave when the review opens and each time the agent finishes a turn (goes from working to idle); for a Claude Code agent the wave also keeps what the turn was asked and answered. Needs an ordo that knows `ordo wave` |
| `AUTO_OPEN` | `0` | `1` opens a review tab in every new worktree workspace |
| `PLACEMENT` | `tab` | `tab` (its own tab, named `ordo`), `split`, `zoomed` or `overlay` |
| `DIRECTION` | `right` | `right` or `down`, for a split |
| `AGENT_PANE` | | always send to this pane id |

## Tests

```bash
bash tests/run.sh
```

The tests run the scripts against a stub `herdr` that records each call, so
they never touch a running herdr.
