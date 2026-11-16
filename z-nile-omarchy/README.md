# z-nile-omarchy

Desktop apps for z-nile on [Omarchy](https://omarchy.org/) (c0257).

## znile.board

An omarchy-shell plugin: a bar icon with the active ticket count that opens a tiled window of every ticket and raft. Its own README, `znile.board/README.md`, has the details.

Install it by linking the folder into the shell's plugins, then enable it:

```bash
ln -s "$PWD/z-nile-omarchy/znile.board" ~/.config/omarchy/plugins/znile.board
omarchy plugin enable znile.board --section right
omarchy restart shell   # the plugin stays loaded, so code changes need a restart
```

Set the repo path in `znile.board/settings.json` (default `~/code/pickman`). The app needs lune (`z-nile/setup.sh --tools`) and, for PR chips, a signed-in `gh`.

Tests: `node --test z-nile-omarchy/znile.board/tests/`
