# mpv.nvim

A Neovim plugin that lets you play music via [mpv](https://mpv.io/) inside Neovim, and control the player directly with custom keybindings.

## Demo

![mpv.nvim picker](https://github.com/felixlazy/assets/blob/master/image/project/mpv.nvim/mpv_nvim_picker.png)

## Features

- Play local or online music directly in Neovim
- Control mpv with Neovim keybindings (play/pause, previous, next, volume, etc.)
- Supports mpv IPC communication
- Easy to configure and extend

## Installation

Make sure [mpv](https://mpv.io/) is installed on your system.

**With [packer.nvim](https://github.com/wbthomason/packer.nvim):**

```lua
use {
  'Wu-Felix/mpv.nvim',
  config = function()
    require('mpv').setup()
  end
}
```

**With [lazy.nvim](https://github.com/folke/lazy.nvim):**

```lua
return {
  'Wu-Felix/mpv.nvim',
  dependencies = {
    "folke/snacks.nvim"
  },
  opts = {}
}
```

## Configuration

Optionally, customize in your `init.lua`:

```lua
opts = {
  ipc_name = "mpv_ipc",
  music_path = "~/OneDrive/PARA/resource/music",
}
```

## Example Keybindings

```lua
  keys = {
    { "<leader>mi", "<cmd>MpvInfo<cr>", desc = "mpv get info" },
    { "<leader>m>", "<cmd>MpvNext<cr>", desc = "mpv next" },
    { "<leader>m<", "<cmd>MpvPrev<cr>", desc = "mpv prev" },
    { "<leader>mk", "<cmd>MpvVolumeUp<cr>", desc = "mpv volume up" },
    { "<leader>mj", "<cmd>MpvVolumeDown<cr>", desc = "mpv volume down" },
    { "<leader>mp", "<cmd>MpvPause<cr>", desc = "mpv pause" },
    { "<leader>mo", "<cmd>MpvPicker<cr>", desc = "mpv pause" },
    { "<leader>ml", "<cmd>MpvSeekForward<cr>", desc = "mpv seek forward 5" },
    { "<leader>mh", "<cmd>MpvSeekBackward<cr>", desc = "mpv seek backward 5" },
    { "<leader>mL", "<cmd>MpvSeekForward 60<cr>", desc = "mpv seek forward 60" },
    { "<leader>mH", "<cmd>MpvSeekBackward 60<cr>", desc = "mpv seek backward 60" },
    { "<leader>m+", "<cmd>MpvSpeedUp<cr>", desc = "mpv speed 0.1" },
    { "<leader>m-", "<cmd>MpvSpeedDown<cr>", desc = "mpv speed -0.1" },
    { "<leader>mq", "<cmd>MpvQuit<cr>", desc = "mpv quit" },
  },
```

## Lualine

```lua
{
      "nvim-lualine/lualine.nvim",
      opts = function(_, opts)
        table.insert(opts.sections.lualine_c, {
          function()
            title = require("mpv.ipc").title
            if title == nil or title == "" then
              return ""
            end
            return " " .. require("mpv.ipc").title
          end,
          color = "@comment.todo",
        })
        return opts
      end,
    }
}
```

![mpv.nvim lualine](https://github.com/felixlazy/assets/blob/master/image/project/mpv.nvim/mpv_nvim_lualine.png)

## Dependencies

- [mpv](https://mpv.io/)
- Neovim 0.7+

## License
