# herdr-ordo

A [herdr](https://herdr.dev) plugin that opens [ordo](https://github.com/FoamScience/ordo)
in a pane beside your agent. You read the agent's diff in ordo's reading order,
note and comment on it, and `:send` the review back to the agent as typed input.

- **Review pane**: ordo on the pane's repository, split beside the chat.
- **Send to the agent**: ordo's `:send` types the review into the workspace's
  agent without pressing Enter, and focuses it, so you read it over and submit.
- **Auto-open**: a new worktree workspace gets a review pane.

The plugin runs ordo and herdr's own CLI. It never edits the worktree.

## Requirements

- herdr ≥ 0.7.5
- `ordo` itself, installed separately, for example `cargo install --path <ordo checkout>`
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
description = "ordo review pane"
```

## In the pane

It is ordo, so everything ordo does applies. For the review loop:

| key / command | does |
| --- | --- |
| `:note <text>` | a note on the selected hunk's symbol |
| `v`, then `c` | select lines in the code pane and comment on them |
| `gc` / `gC` | next / previous comment |
| `:send` | type the review into the agent, notes and comments, anchored `path:line` |
| `:send all` | the same, with ordo's own findings added |
| `:yank` | copy the review to the clipboard instead |

Which agent receives it:
- `AGENT_PANE`, when set.
- Otherwise the only agent in the workspace.
- Otherwise the only agent in the review pane's own tab.

With several candidates and no way to tell them apart, `:send` refuses and
names them.

## Configuration

`$(herdr plugin config-dir foamscience.ordo)/config.env` is a plain shell file
of `KEY=value` lines. Quote any value with spaces.

| key | default | meaning |
| --- | --- | --- |
| `ORDO_BIN` | `ordo` | the ordo binary |
| `ORDO_ARGS` | `zz` | what to review: `zz` is the uncommitted work; `"main...zz"` is everything since the branch left `main`, uncommitted included |
| `AUTO_OPEN` | `1` | `0` keeps new worktree workspaces without a pane |
| `PLACEMENT` | `split` | `split`, `zoomed`, `tab` or `overlay` |
| `DIRECTION` | `right` | `right` or `down`, for a split |
| `AGENT_PANE` | | always send to this pane id |

## Tests

```bash
bash tests/run.sh
```

The tests run the scripts against a stub `herdr` that records each call, so
they never touch a running herdr.
