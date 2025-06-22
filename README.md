# mpv.nvim

A Neovim plugin that allows you to play music via [mpv](https://mpv.io/) inside Neovim, and control the mpv player directly with custom keybindings.

## Features

- Play local or online music directly inside Neovim
- Control mpv with Neovim keybindings (play/pause, previous, next, volume, etc.)
- Supports mpv IPC communication
- Easy to configure and extend

## Installation

Make sure [mpv](https://mpv.io/) is installed on your system.

Install with [packer.nvim](https://github.com/wbthomason/packer.nvim):

```lua
use {
  'Wu-Felix/mpv.nvim',
  config = function()
    require('mpv').setup()
  end
}
```

Install with [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
return {
  'Wu-Felix/mpv.nvim',
  opts={}
}
```

## Configuration

Optional: Customize in your `init.lua`:

```lua
  opts = {
    ipc_name = "mpv_ipc",
    music_path = "~/OneDrive/PARA/resource/music",
  },
```

## Example Keybindings

```lua
  keys = {
    { "<leader>mi", "<cmd>MpvInfo<cr>", desc = "mpv get info" },
    { "<leader>m>", "<cmd>MpvNext<cr>", desc = "mpv next" },
    { "<leader>m<", "<cmd>MpvPrev<cr>", desc = "mpv prev" },
    { "<leader>mk", "<cmd>MpvVolumeUp<cr>", desc = "mpv volume up" },
    { "<leader>mj", "<cmd>MpvVolumDown<cr>", desc = "mpv volume down" },
    { "<leader>mp", "<cmd>MpvPause<cr>", desc = "mpv pause" },
    { "<leader>mo", "<cmd>MpvPlay<cr>", desc = "mpv play" },
  },
```

## Dependencies

- [mpv](https://mpv.io/)
- Neovim 0.7+

## License
