local M = {}

-- 获取平台动态库扩展名
function M.get_lib_ext()
	if vim.fn.has("mac") == 1 then
		return "dylib"
	elseif vim.fn.has("win32") == 1 then
		return "dll"
	else
		return "so"
	end
end

-- 获取动态库基本名（是否加 lib 前缀）
function M.get_lib_basename(name)
	if vim.fn.has("win32") == 1 then
		return name
	else
		return "lib" .. name
	end
end

-- 拼接路径
function M.build_lib_path(plugin_root, mode, lib_basename, lib_ext)
	return string.format("%s/target/%s/%s.%s", plugin_root, mode, lib_basename, lib_ext)
end

-- 查找 release/debug 中存在的动态库路径
function M.find_existing_lib_path(plugin_root, lib_basename, lib_ext)
	for _, mode in ipairs({ "release", "debug" }) do
		local path = M.build_lib_path(plugin_root, mode, lib_basename, lib_ext)
		local f = io.open(path, "r")
		if f then
			f:close()
			return path
		end
	end
	return nil
end

-- 防止重复添加路径
function M.add_cpath_once(pattern)
	for entry in string.gmatch(package.cpath, "([^;]+)") do
		if entry == pattern then
			return
		end
	end
	package.cpath = package.cpath .. ";" .. pattern
	-- vim.notify("Added to package.cpath: " .. pattern, vim.log.levels.DEBUG)
end

-- 主入口：加载 Rust 动态库
--- @param lib_name string Rust 编译出的库名（不含 lib / .so 等）
--- @param plugin_path string 插件中任意 lua 文件路径（如 "lua/myplugin/init.lua"）
--- @param require_name string? 可选 Lua 模块名，默认为 lib_name
function M.load_rust_lib(lib_name, plugin_path, require_name)
	require_name = require_name or lib_name

	local lib_ext = M.get_lib_ext()
	local lib_basename = M.get_lib_basename(lib_name)

	local matches = vim.api.nvim_get_runtime_file(plugin_path, false)
	if #matches == 0 then
		error("Runtime file not found: " .. plugin_path)
	end

	local plugin_root = vim.fn.fnamemodify(matches[1], ":h:h:h")
	local lib_path = M.find_existing_lib_path(plugin_root, lib_basename, lib_ext)

	if not lib_path then
		error(
			string.format(
				'Rust library not found.\nTried:\n  %s\n  %s\nPlease run "cargo build --release" or "cargo build".',
				M.build_lib_path(plugin_root, "release", lib_basename, lib_ext),
				M.build_lib_path(plugin_root, "debug", lib_basename, lib_ext)
			)
		)
	end

	local lib_dir = vim.fn.fnamemodify(lib_path, ":h")
	local pattern = string.format("%s/?.%s", lib_dir, lib_ext)
	M.add_cpath_once(pattern)

	local ok, result = pcall(require, require_name)
	if not ok then
		error(string.format("Failed to load Rust library '%s': %s", require_name, result))
	end

	return result
end

return M
