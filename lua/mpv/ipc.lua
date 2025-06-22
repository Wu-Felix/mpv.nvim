local M = { pipe = nil }
local config = require("mpv.config")
local uv = vim.uv

local connected = false
M.req_id = 0
M.pending = {} -- 储存回调: request_id -> function(data)

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
			config.music_path,
			"--input-ipc-server=" .. config.ipc_path,
			"--idle=yes",
			"--force-window=no",
			"--no-terminal",
			"--no-video",
			"--shuffle",
			"--volume=50",
			"--loop-playlist",
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

		local buffer = ""
		M.pipe:read_start(function(err2, data)
			if data then
				buffer = buffer .. data
				for line in buffer:gmatch("[^\r\n]+") do
					vim.schedule(function()
						local ok, decoded = pcall(vim.fn.json_decode, line)
						if not ok or not decoded then
							return
						end

						-- get_property 响应
						if decoded.request_id then
							local cb = M.pending[decoded.request_id]
							if cb then
								cb(decoded.data)
								M.pending[decoded.request_id] = nil
							end
						end

						-- 事件，如 start-file
						if decoded.event == "start-file" then
							vim.defer_fn(function()
								M.get_playback_info()
							end, 10)
						end
					end)
				end
				buffer = "" -- 每次处理完清空
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

function M.send_to_mpv(command_table, callback)
	if not M.pipe then
		vim.notify("mpv 未连接", vim.log.levels.ERROR)
		return
	end

	M.req_id = M.req_id + 1
	command_table.request_id = M.req_id

	local json = vim.fn.json_encode(command_table)
	M.pipe:write(json .. "\n")

	if callback then
		M.pending[M.req_id] = callback
	end
end

-- 下一首
function M.mpv_playlist_next()
	M.send_to_mpv({ command = { "playlist-next", "force" } })
end

-- 上一首
function M.mpv_playlist_prev()
	M.send_to_mpv({ command = { "playlist-prev", "force" } })
end

-- 暂停/播放切换
function M.mpv_toggle_pause()
	M.send_to_mpv({ command = { "cycle", "pause" } })
end

function M.get_volume()
	M.send_to_mpv({ command = { "get_property", "volume" } }, function(data)
		vim.notify("当前音量: " .. tostring(data))
	end)
end

function M.get_pause()
	M.send_to_mpv({ command = { "get_property", "pause" } }, function(data)
		vim.notify("当前状态: " .. (data and "已暂停" or "播放中"))
	end)
end

function M.get_title()
	M.send_to_mpv({ command = { "get_property", "media-title" } }, function(title)
		if title then
			vim.notify("当前播放: " .. title, vim.log.levels.INFO, { title = "mpv" })
		else
			vim.notify("未获取到标题（可能未播放）", vim.log.levels.WARN, { title = "mpv" })
		end
	end)
end

function M.format_time(seconds)
	seconds = tonumber(seconds)
	if not seconds then
		return "??:??"
	end
	local m = math.floor(seconds / 60)
	local s = math.floor(seconds % 60)
	return string.format("%02d:%02d", m, s)
end

function M.get_playback_info()
	local info = {}
	local collected = 0
	local total = 4

	local function show_info()
		local msg = string.format(
			"%s [%s / %s] (%.1f%%)",
			info["media-title"] or "未知",
			M.format_time(info["time-pos"]),
			M.format_time(info["duration"]),
			tonumber(info["percent-pos"] or 0)
		)
		vim.notify(msg, vim.log.levels.INFO, { title = "mpv 播放信息" })
	end

	local function make_cb(prop)
		return function(data)
			info[prop] = data
			collected = collected + 1
			if collected == total then
				show_info()
			end
		end
	end

	M.send_to_mpv({ command = { "get_property", "media-title" } }, make_cb("media-title"))
	M.send_to_mpv({ command = { "get_property", "time-pos" } }, make_cb("time-pos"))
	M.send_to_mpv({ command = { "get_property", "duration" } }, make_cb("duration"))
	M.send_to_mpv({ command = { "get_property", "percent-pos" } }, make_cb("percent-pos"))
end
-- 音量调节
function M.mpv_volume_up()
	M.send_to_mpv({ command = { "add", "volume", 5 } }) -- 每次加 5
	vim.defer_fn(function()
		M.get_volume()
	end, 1000)
end
function M.mpv_volume_down()
	M.send_to_mpv({ command = { "add", "volume", -5 } }) -- 每次减 5
	vim.defer_fn(function()
		M.get_volume()
	end, 1000)
end

vim.api.nvim_create_user_command("MpvNext", function()
	M.mpv_playlist_next()
end, { desc = "mpv playlist next" })

vim.api.nvim_create_user_command("MpvPrev", function()
	M.mpv_playlist_prev()
end, { desc = "mpv playlist perv" })

vim.api.nvim_create_user_command("MpvPlay", function()
	M.start_mpv()
	vim.defer_fn(function()
		M.connect()
	end, 2000)
end, { desc = "mpv playlist perv" })

vim.api.nvim_create_user_command("MpvPause", function()
	M.mpv_toggle_pause()
end, { desc = "Toggle mpv pause/play" })

vim.api.nvim_create_user_command("MpvVolumeUp", function()
	M.mpv_volume_up()
end, { desc = "Increase mpv volume" })

vim.api.nvim_create_user_command("MpvVolumeDown", function()
	M.mpv_volume_down()
end, { desc = "Decrease mpv volume" })

vim.api.nvim_create_user_command("MpvTitle", function()
	M.get_title()
end, { desc = "mpv title" })

vim.api.nvim_create_user_command("MpvInfo", function()
	M.get_playback_info()
end, { desc = "mpv info" })
return M
