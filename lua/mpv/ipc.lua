local M = {}

function M.set_pipe_path(path)
	M.pipe_path = path
	if vim.fn.has("win32") == 1 then
		PIPE_PATH = "\\\\.\\pipe\\" .. path
	else
		PIPE_PATH = "/tmp/" .. path
	end
end
-- 工具：格式化时间（秒转 MM:SS）
local function time_fmt(t)
	if not t then
		return "--:--"
	end
	local minutes = math.floor(t / 60)
	local seconds = math.floor(t % 60)
	return string.format("%02d:%02d", minutes, seconds)
end

-- 发送任意命令给 mpv
-- command_array 是 mpv JSON IPC 命令数组，比如 {"set_property", "pause", true}
function M.send_mpv_command(command_array)
	local handle = io.open(PIPE_PATH, "r+")
	if not handle then
		vim.notify("Failed to connect to MPV socket: " .. PIPE_PATH, vim.log.levels.ERROR)
		return nil
	end

	local request = vim.fn.json_encode({ command = command_array })
	handle:write(request .. "\n")
	handle:flush()

	local response = handle:read("*l")
	handle:close()

	if response then
		local ok, decoded = pcall(vim.fn.json_decode, response)
		if ok and decoded and decoded.error == "success" then
			return decoded
		else
			vim.notify("MPV returned error: " .. (decoded and decoded.error or "unknown"), vim.log.levels.WARN)
		end
	end

	return nil
end

-- 获取单个属性值，比如 "media-title", "pause"
function M.get_property(prop)
	local handle = io.open(PIPE_PATH, "r+")
	if not handle then
		vim.notify("Could not open mpv socket: " .. PIPE_PATH, vim.log.levels.ERROR)
		return nil
	end

	local request = vim.fn.json_encode({ command = { "get_property", prop } })
	handle:write(request .. "\n")
	handle:flush()

	local response = handle:read("*l")
	handle:close()

	if not response then
		vim.notify("No response from mpv for '" .. prop .. "'", vim.log.levels.WARN)
		return nil
	end

	local ok, decoded = pcall(vim.fn.json_decode, response)
	if not ok or not decoded or decoded.data == nil then
		vim.notify("Failed to parse response for '" .. prop .. "'", vim.log.levels.WARN)
		return nil
	end

	return decoded.data
end

-- 一次请求多个属性，返回 key-value table
function M.get_properties(props)
	local handle = io.open(PIPE_PATH, "r+")
	if not handle then
		vim.notify("Could not open mpv socket: " .. PIPE_PATH, vim.log.levels.ERROR)
		return nil
	end

	for _, prop in ipairs(props) do
		local request = vim.fn.json_encode({ command = { "get_property", prop } })
		handle:write(request .. "\n")
	end
	handle:flush()

	local results = {}
	for _, prop in ipairs(props) do
		local line = handle:read("*l")
		if line then
			local ok, decoded = pcall(vim.fn.json_decode, line)
			if ok and decoded and decoded.data ~= nil then
				results[prop] = decoded.data
			end
		end
	end

	handle:close()
	return results
end

-- 获取当前媒体标题（带前缀）
function M.get_mpv_title()
	local title = M.get_property("media-title")
	if title then
		return "  " .. title
	else
		return ""
	end
end

-- 显示当前播放状态和信息
function M.show_title()
	local info = M.get_properties({ "media-title", "time-pos", "duration", "pause" })
	if not info or not info["media-title"] then
		vim.notify("Unable to retrieve MPV media title", vim.log.levels.ERROR)
		return
	end

	local message = string.format("  %s", info["media-title"])
	vim.notify(message, vim.log.levels.INFO)
end

function M.show_title_info()
	local info = M.get_properties({ "media-title", "time-pos", "duration", "pause" })
	if not info or not info["media-title"] then
		vim.notify("Unable to retrieve MPV media title", vim.log.levels.ERROR)
		return
	end

	local message = string.format(
		"  %s\n  %s / %s",
		info["media-title"],
		time_fmt(info["time-pos"]),
		time_fmt(info["duration"])
	)

	vim.notify(message, vim.log.levels.INFO)
end

function M.show_volume()
	local info = M.get_properties({ "media-title", "time-pos", "duration", "pause", "volume" })
	if not info or not info["media-title"] then
		vim.notify("Unable to retrieve MPV media title", vim.log.levels.ERROR)
		return
	end

	local message = string.format("   %d%%", info["volume"] or 0)

	vim.notify(message, vim.log.levels.INFO)
end

function M.set_speed(delta)
	local current = M.get_property("speed")
	if not current then
		vim.notify("Failed to get current speed", vim.log.levels.WARN)
		return
	end

	local new_speed = math.max(0.1, current + delta) -- 限制最低速度为 0.1x
	M.send_mpv_command({ "set_property", "speed", new_speed })

	vim.defer_fn(function()
		local confirmed = M.get_property("speed")
		if confirmed then
			vim.notify(string.format("󰓅 %.1fx", confirmed), vim.log.levels.INFO)
		end
	end, 100)
end

function M.reset_speed()
	M.send_mpv_command({ "set_property", "speed", 1 })
	vim.defer_fn(function()
		local confirmed = M.get_property("speed")
		if confirmed then
			vim.notify(string.format("󰓅 %.1fx", confirmed), vim.log.levels.INFO)
		end
	end, 100)
end

M.toggle_pause = function()
	M.send_mpv_command({ "cycle", "pause" })
end

M.next_track = function()
	M.send_mpv_command({ "playlist-next", "force" })
end

M.prev_track = function()
	M.send_mpv_command({ "playlist-prev", "force" })
end

M.volume_up = function()
	M.send_mpv_command({ "add", "volume", 10 })
end

M.volume_down = function()
	M.send_mpv_command({ "add", "volume", -10 })
end

M.seek_forward = function()
	M.send_mpv_command({ "seek", 10, "relative" }) -- 快进 10 秒
end

M.seek_backward = function()
	M.send_mpv_command({ "seek", -10, "relative" }) -- 快退 10 秒
end

M.toggle_playlist = function()
	M.send_mpv_command({ "script-message", "playlistmanager", "show", "playlist" })
end

M.quit = function()
	M.send_mpv_command({ "quit-watch-later" })
end
return M
