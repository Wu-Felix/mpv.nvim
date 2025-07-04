local M = { pipe = nil }
local config = require("mpv.config")
local uv = vim.uv
local flag = false
local connected = false

M.send_queue = {}
M.connecting = false
M.req_id = 0
M.pending = {} -- 储存回调: request_id -> function(data)
M.title = ""

function M.is_mpv_running()
	if flag then
		return true
	end
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

function M.start_mpv(path)
	local music_path
	if path == "" then
		music_path = path
	else
		music_path = config.music_path
	end
	if not M.is_mpv_running() then
		vim.system({
			"mpv",
			music_path,
			"--input-ipc-server=" .. config.ipc_path,
			"--idle=yes",
			"--force-window=no",
			"--no-terminal",
			"--no-video",
			"--shuffle",
			"--volume=50",
			"--loop-playlist",
			"--no-resume-playback",
		}, {
			detach = true,
		})
	end
end

function M.mpv_play(path)
	if M.is_mpv_running() then
		if vim.fn.has("win32") == 1 then
			os.execute("taskkill /IM mpv.exe /F")
		else
			-- 等待命令执行完成，避免 nvim 退出太快
			os.execute("pkill -f 'mpv.*" .. config.ipc_path .. "'")
		end
	end
	connected = false
	vim.system({
		"mpv",
		path,
		"--input-ipc-server=" .. config.ipc_path,
	}, {
		detach = true,
	})
end
function M.connect()
	if connected or M.connecting then
		return
	end
	M.connecting = true
	M.pipe = uv.new_pipe(false)
	M.pipe:connect(config.ipc_path, function(err)
		M.connecting = false
		if err then
			vim.notify("连接 mpv 失败: " .. err, vim.log.levels.ERROR)
			return
		end
		connected = true
		vim.notify("已连接 mpv", vim.log.levels.INFO)
		M.start_time_title()
		local buffer = ""
		M.pipe:read_start(function(_, data)
			if data then
				buffer = buffer .. data
				for line in buffer:gmatch("[^\r\n]+") do
					vim.schedule(function()
						local ok, decoded = pcall(vim.fn.json_decode, line)
						if not ok or not decoded then
							return
						end
						if decoded.request_id then
							local cb = M.pending[decoded.request_id]
							if cb then
								cb(decoded.data)
								M.pending[decoded.request_id] = nil
							end
						end
						if decoded.event == "start-file" then
							vim.defer_fn(function()
								M.get_playback_info()
							end, 10)
						end
					end)
				end
				buffer = ""
			end
		end)

		-- ⚠️连接成功后发送所有排队的命令
		for _, item in ipairs(M.send_queue) do
			M.send_to_mpv(item.cmd, item.cb)
		end
		M.send_queue = {}
	end)
end

function M.auto_start_mpv()
	if not M.is_mpv_running() then
		vim.system({
			"mpv",
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
		flag = true
		vim.defer_fn(function()
			M.connect()
		end, 500)
	end
end

function M.send_to_mpv(command_table, callback)
	if not M.pipe or not M.pipe:is_active() or M.connecting then
		table.insert(M.send_queue, { cmd = command_table, cb = callback })
		if not M.connecting then
			M.connect()
		end
		return
	end

	M.req_id = M.req_id + 1
	command_table.request_id = M.req_id

	local json = vim.json.encode(command_table)
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

function M.play_file(path)
	M.send_to_mpv({ command = { "loadfile", path, "replace" } })
end

function M.get_volume()
	M.send_to_mpv({ command = { "get_property", "volume" } }, function(data)
		vim.notify("当前音量: " .. tostring(data))
	end)
end
-- 快进 10 秒
function M.mpv_seek_forward(seconds)
	seconds = seconds or 5
	M.send_to_mpv({ command = { "seek", seconds, "relative" } })
end

-- 快退 10 秒
function M.mpv_seek_backward(seconds)
	seconds = seconds or 5
	M.send_to_mpv({ command = { "seek", -seconds, "relative" } })
end

function M.set_speed(rate)
	rate = tonumber(rate)
	if not rate or rate <= 0 then
		vim.notify("无效倍速：" .. tostring(rate), vim.log.levels.ERROR)
		return
	end
	M.send_to_mpv({ command = { "set_property", "speed", rate } })
end

function M.get_speed()
	M.send_to_mpv({ command = { "get_property", "speed" } }, function(data)
		vim.notify("当前播放速度: " .. tostring(data) .. "x")
	end)
end

function M.adjust_speed(delta)
	M.send_to_mpv({ command = { "get_property", "speed" } }, function(current)
		local new_speed = math.max(0.1, current + delta)
		M.set_speed(new_speed)
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
			(info["media-title"] or "未知"):gsub("%%#", "%%"),
			M.format_time(info["time-pos"]),
			M.format_time(info["duration"]),
			tonumber(info["percent-pos"] or 0)
		)
		-- M.title = (info["media-title"] or "未知"):gsub("%%#", "%%") or ""

		M.title = msg or ""
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

function M.get_path(callback)
	local info = {}
	local collected = 0
	local total = 2

	local function get_work_path()
		if not info["path"] or not info["working"] then
			vim.notify("mpv 属性 path 或 working-directory 未获取到", vim.log.levels.ERROR)
			if callback then
				callback(config.music_path)
			end
			return
		end

		local function is_absolute(p)
			return p:match("^%a:[/\\]") or p:match("^\\\\")
		end

		local cleaned_path = info["path"]:gsub("^%./", "")
		local abs_path
		local dir
		if vim.fn.has("win32") == 1 then
			if is_absolute(cleaned_path) then
				abs_path = vim.fn.fnamemodify(cleaned_path, ":p")
			else
				abs_path = vim.fn.fnamemodify(info["working"] .. "/" .. cleaned_path, ":p")
			end
			dir = vim.fn.fnamemodify(abs_path, ":h"):gsub("[/\\]%.?$", "") .. "/"
		else
			dir = vim.fn.fnamemodify(info["path"], ":h")
		end
		if callback then
			callback(dir)
		end
	end

	local function make_cb(prop)
		return function(data)
			info[prop] = data
			collected = collected + 1
			if collected == total then
				get_work_path()
			end
		end
	end

	M.send_to_mpv({ command = { "get_property", "working-directory" } }, make_cb("working"))
	M.send_to_mpv({ command = { "get_property", "path" } }, make_cb("path"))
end

function M.quit()
	M.send_to_mpv({ command = { "quit" } })
	M.title = ""
	vim.notify("mpv 已退出", vim.log.levels.INFO, { title = "mpv" })
end

function M.setup()
	-- 只注册一次 autocmd（不在 start_mpv 里注册）
	-- vim.api.nvim_create_autocmd("VimLeavePre", {
	-- 	once = true, -- 避免重复触发
	-- 	callback = function()
	-- 		if vim.fn.has("win32") == 1 then
	-- 			os.execute("taskkill /IM mpv.exe /F")
	-- 		else
	-- 			-- 等待命令执行完成，避免 nvim 退出太快
	-- 			os.execute("pkill -f 'mpv.*" .. config.ipc_path .. "'")
	-- 		end
	-- 	end,
	-- })

	vim.api.nvim_create_user_command("MpvNext", function()
		M.mpv_playlist_next()
	end, { desc = "mpv playlist next" })

	vim.api.nvim_create_user_command("MpvPrev", function()
		M.mpv_playlist_prev()
	end, { desc = "mpv playlist perv" })

	vim.api.nvim_create_user_command("MpvPlay", function(opts)
		if opts.args == "" then
			M.start_mpv()
		else
			M.mpv_play(vim.fn.expand(opts.args))
		end
		vim.defer_fn(function()
			M.connect()
		end, 500)
	end, {
		desc = "mpv playlist perv",
		nargs = "?",
		complete = "file",
	})

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

	vim.api.nvim_create_user_command("MpvSeekForward", function(opts)
		if opts.args == "" then
			M.mpv_seek_forward()
		else
			M.mpv_seek_forward(opts.args)
		end
	end, { desc = "mpv seek backward", nargs = "?" })

	vim.api.nvim_create_user_command("MpvSeekBackward", function(opts)
		if opts.args == "" then
			M.mpv_seek_backward()
		else
			M.mpv_seek_backward(opts.args)
		end
	end, { desc = "mpv seek backward", nargs = "?" })

	vim.api.nvim_create_user_command("MpvSpeed", function(opts)
		local rate = tonumber(opts.args)
		if rate then
			M.set_speed(rate)
		else
			M.get_speed()
		end
	end, {
		nargs = "?",
		desc = "设置或获取 mpv 播放速度。示例：:MpvSpeed 1.5",
	})

	vim.api.nvim_create_user_command("MpvSpeedUp", function()
		M.adjust_speed(0.1)
		vim.defer_fn(function()
			M.get_speed()
		end, 100)
	end, { desc = "播放速度 +0.1" })

	vim.api.nvim_create_user_command("MpvSpeedDown", function()
		M.adjust_speed(-0.1)
		vim.defer_fn(function()
			M.get_speed()
		end, 100)
	end, { desc = "播放速度 -0.1" })

	vim.api.nvim_create_user_command("MpvPicker", function()
		local ok_snacks, snacks = pcall(require, "snacks.picker")
		if not ok_snacks then
			vim.notify("snacks.nvim 未安装，无法打开选择器", vim.log.levels.ERROR)
			return
		end
		M.auto_start_mpv()
		M.get_path(function(path)
			require("snacks.picker").files({
				cwd = path, -- 或其他目录
				ignored = true,
				preview = function(item)
					if not item then
						return
					end
					-- local path = vim.fn.expand("~/OneDrive/PARA/resource/music/" .. item.file)
					local path = Snacks.picker.util.path(item.item)
					if vim.fn.executable("mediainfo") == 1 then
						vim.system({ "mediainfo", path }, { text = true }, function(obj)
							vim.schedule(function()
								if obj.code == 0 then
									item.preview:notify(obj.stdout, info)
								else
									item.preview:notify(obj.stderr, error)
								end
							end)
						end)
					else
						item.preview:notify(path, info)
					end
				end,
				actions = {
					confirm = function(picker, item)
						if not item then
							return
						end
						local path = vim.fn.expand(path .. "/" .. item.file)
						M.play_file(path)
						picker:close()
					end,
				},
			})
		end)
	end, {})

	vim.api.nvim_create_user_command("MpvGetPath", function()
		M.get_path()
	end, { desc = "获取播放目录" })
	vim.api.nvim_create_user_command("MpvQuit", function()
		M.quit()
	end, { desc = "关闭mpv" })
end

function M.start_time_title(time)
	if time == nil then
		time = config.mpv_time or 1000
	end
	local timer = uv.new_timer()
	timer:start(
		0,
		time,
		vim.schedule_wrap(function()
			local info = {}
			local collected = 0
			local total = 3
			local function show_info()
				local msg = string.format(
					"%s (%s / %s) ",
					(info["media-title"] or "未知"):gsub("%%#", "%%"),
					M.format_time(info["time-pos"]),
					M.format_time(info["duration"])
				)
				M.title = msg or ""
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
		end)
	)
end
return M
