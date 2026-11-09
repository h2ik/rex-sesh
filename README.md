# rex-sesh

A [sesh](https://github.com/joshmedeski/sesh)-style session picker for [Rex](https://www.superlogical.com/rex), and macOS notifications for agents that need you.

The picker opens fzf in a Rex floating pane. It lists your Rex sessions, your sesh configs, and your zoxide folders. If you pick a session, Rex switches to it. If you pick a folder, Rex switches to the session with the same name as that folder. If no such session exists, the picker makes one first.

Each session row shows a colored dot when a program in that session reports its status with [OSC 7501](https://www.superlogical.com/rex/docs/build/program-status). Claude Code reports its status this way.

| Dot | State | Meaning |
| --- | --- | --- |
| Yellow | `blocked` | The program waits for you, for example for an approval. |
| Red | `error` | The program failed and stopped. |
| Green | `done` | The program finished, and you did not look yet. |
| Blue | `working` | The program is running. |

## Contents

| Path | Description |
| --- | --- |
| `bin/rex-sesh` | The picker script. Rex runs it in a floating pane. |
| `rex/rex-sesh.lua` | A Rex config module. It defines the `sesh_picker` action and its key. |
| `rex/rex-notify.lua` | A `rex do` listener. It sends a macOS notification when a program changes to `blocked`. |
| `launchd/local.rex-notify.plist.in` | A launchd template that keeps the listener running. |
| `install.sh` | The installer and uninstaller. |

## Requirements

- macOS with the Rex app.
- The `rex` CLI. The installer finds it in your `PATH` or in the Rex app.
- `zsh`, `fzf`, `jq`, `zoxide`, and `fd`.
- `terminal-notifier`, for notifications only.
- Optional: `eza` for folder previews, and `sesh` for sesh configs.

To install the tools, run this command:

```sh
brew install fzf jq zoxide fd terminal-notifier eza
```

## Install

1. Clone the repository:

   ```sh
   git clone git@github.com:h2ik/rex-sesh.git ~/Projects/h2ik/rex-sesh
   ```

2. Run the installer:

   ```sh
   ~/Projects/h2ik/rex-sesh/install.sh
   ```

3. In Rex, press `ctrl+space`, then `shift+t`.

The installer does these steps:

1. It checks that the tools are installed.
2. It links `bin/rex-sesh` into `BIN_DIR`.
3. It links the Lua files into the Rex config folder.
4. It adds a marked block to `init.lua` that loads the module.
5. It installs the launchd agent `local.rex-notify` and starts it.
6. It checks `init.lua` and reloads the Rex config.

The installer makes symbolic links. Thus, a `git pull` updates your setup, and you do not have to install again. To copy the files instead, add `--copy`.

If a file already exists at a target path, the installer moves it to `<name>.bak.<time>` first.

### Options

| Option | Description |
| --- | --- |
| `--no-notify` | Do not install the notification listener. |
| `--copy` | Copy the files. Do not link them. |

| Environment variable | Default | Description |
| --- | --- | --- |
| `BIN_DIR` | `~/.local/bin` | The folder for `rex-sesh`. |
| `REX_CONFIG_DIR` | `${XDG_CONFIG_HOME:-~/.config}/rex` | The Rex config folder. |
| `REX_SESH_KEY` | `ctrl+space>shift+t` | The key for the picker. |
| `REX_SERVER` | The socket of the Mac app | The Rex server address for the listener. |

For example, to install into `~/.bin` with the key `cmd+shift+s`, run this command:

```sh
BIN_DIR=~/.bin REX_SESH_KEY='cmd+shift+s' ./install.sh
```

### Configure the module yourself

If you do not want the installer to edit `init.lua`, add this block yourself:

```lua
require("rex-sesh").setup{
  bin    = os.getenv("HOME") .. "/.local/bin/rex-sesh",
  key    = "ctrl+space>shift+t",
  bounds = { 0.1, 0.15, 0.8, 0.7 },
}
```

All options are optional. If you do not set `bin`, the module looks in `~/.local/bin`, `~/.bin`, `~/bin`, `/opt/homebrew/bin`, and `/usr/local/bin`. If you do not set `key`, the module adds no key, and you can run the action from the command palette.

## Use the picker

| Key | Action |
| --- | --- |
| `Enter` | Switch to the selected session or folder. |
| `ctrl-a` | Show all rows. |
| `ctrl-t` | Show Rex sessions only. |
| `ctrl-g` | Show sesh configs only. |
| `ctrl-x` | Show zoxide folders only. |
| `ctrl-f` | Find folders two levels below your home folder. |
| `ctrl-d` | Close the selected Rex session. |
| `Tab`, `Shift-Tab` | Move down and up. |

The `ctrl-a` list hides a folder if a session with the same name exists. The `ctrl-x` and `ctrl-f` lists show all folders.

`ctrl-d` does not close the session that the picker runs in.

The dots show the state at the time that the list loads. To read the states again, press `ctrl-a` or `ctrl-t`.

## Notifications

Rex has its own notifications for program status. To turn them on, open **Settings > Notifications > Program Activity** and turn on **Show system notifications**. Rex sends these notifications only while Rex is in the background.

The `rex-notify` listener covers the other case. It sends a notification when Rex is in front and a program changes to `blocked`. If you click the notification, Rex shows the session and tab of that program.

To send notifications for other states, edit the `NOTIFY` table at the top of `rex/rex-notify.lua`. Then restart the listener:

```sh
launchctl kickstart -k "gui/$(id -u)/local.rex-notify"
```

The listener writes its log to `~/Library/Logs/rex-notify.log`.

To test the listener without the front-app check, run this command:

```sh
REX_NOTIFY_ALWAYS=1 rex do rex/rex-notify.lua --all --for 30s
```

## Remote Control

The picker switches sessions with the Rex client action `session.select`. This action works only if Remote Control is on. To turn it on, open **Settings > Server > Client Info** and turn on **Remote Control**.

If the switch fails, the floating pane shows `CONNECT FAILED` and waits for a key.

## Uninstall

Run this command:

```sh
./install.sh uninstall
```

The uninstaller stops the listener and removes its plist. It also removes the marked block from `init.lua`. It removes only the links that point into this repository. Copied files stay in place.

## License

MIT. See [LICENSE](LICENSE).
