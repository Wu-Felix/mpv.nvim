local M = {}

local defaults_opts = require("mpv.config")
local ipc = require("mpv.ipc")
function M.setup(opts)
	-- 合并 opts 到 ipc 中，并保存回 ipc
	local result_opts = vim.tbl_deep_extend("force", {}, defaults_opts or {}, opts or {})
	-- 设置 pipe_path（假设是配置字段）
	ipc.set_pipe_path(result_opts.pipe_path)
end
return M
