local M = {}
local config = require("mpv.config")
local mpv_ipc = require("mpv.ipc")
function M.setup(opts)
	for k, v in pairs(opts or {}) do
		config[k] = v
	end
	config.music_path = vim.fn.expand(config.music_path)
	if vim.fn.has("win32") == 1 then
		config.ipc_path = [[\\.\pipe\]] .. config.ipc_name
	else
		config.ipc_path = "/tmp/" .. config.ipc_name
	end
end
return M
