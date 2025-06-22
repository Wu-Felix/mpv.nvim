local M = {}
local config = require("mpv.config")
local mpv_ipc = require("mpv.ipc")
function M.setup()
	print(config.ipc_path)
	mpv_ipc.start_mpv()
	vim.defer_fn(function()
		mpv_ipc.connect()
	end, 2000)
end
return M
