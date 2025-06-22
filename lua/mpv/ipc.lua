local M = { pipe = nil }
local config = require("mpv.config")
local uv = vim.uv

local connected = false

function M.is_mpv_running()
	if vim.fn.has("win32") == 1 then
		local handle = io.popen('tasklist /FI "IMAGENAME eq mpv.exe"')
		if not handle then
			return false
		end
		local result = handle:read("*a")
		handle:close()
		return result:match("mpv.exe") ~= nil
	else
		local cmd = 'pgrep -f "mpv.*' .. config.ipc_path .. '"'
		local handle = io.popen(cmd)
		if not handle then
			return false
		end
		local result = handle:read("*a")
		handle:close()
		return result ~= nil and result ~= ""
	end
end

function M.start_mpv()
	local path = vim.fn.glob(config.music_path .. "/*", false, true)[1]
	if not path then
		vim.notify("未找到音乐文件", vim.log.levels.WARN)
		return
	end

	if not M.is_mpv_running() then
		vim.system({
			"mpv",
			path,
			"--input-ipc-server=" .. config.ipc_path,
			"--idle=yes",
			"--force-window=no",
			"--no-terminal",
			"--no-video",
			"--shuffle",
			"--loop=inf",
			"--volume=50",
		}, {
			detach = true,
		})
	end
end

function M.connect()
	if connected then
		return
	end
	M.pipe = uv.new_pipe(false)
	M.pipe:connect(config.ipc_path, function(err)
		if err then
			vim.notify("连接 mpv 失败: " .. err, vim.log.levels.ERROR)
			return
		end
		connected = true
		vim.notify("已连接 mpv", vim.log.levels.INFO)

		M.pipe:read_start(function(err, data)
			if data then
				vim.schedule(function()
					print("[mpv响应]:", data)
				end)
			end
		end)
	end)
end

-- 只注册一次 autocmd（不在 start_mpv 里注册）
vim.api.nvim_create_autocmd("VimLeavePre", {
	once = true, -- 避免重复触发
	callback = function()
		if vim.fn.has("win32") == 1 then
			os.execute("taskkill /IM mpv.exe /F")
		else
			-- 等待命令执行完成，避免 nvim 退出太快
			os.execute("pkill -f 'mpv.*" .. config.ipc_path .. "'")
		end
	end,
})
return M
