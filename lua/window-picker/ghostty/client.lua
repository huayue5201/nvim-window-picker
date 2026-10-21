local M = {}

-- Ghostty (macOS) has no IPC socket, but it ships an AppleScript dictionary
-- (Ghostty.sdef) that can enumerate windows/tabs/terminals and focus them.

local rs = string.char(30) -- record separator
local us = string.char(31) -- unit separator

-- `working directory` is the cwd of the terminal's foreground process.
local LIST_SCRIPT = [[
set rs to (ASCII character 30)
set us to (ASCII character 31)
if application "Ghostty" is not running then return ""
tell application "Ghostty"
	set out to ""
	repeat with w in windows
		set wid to (id of w) as text
		set wname to (name of w) as text
		repeat with t in tabs of w
			set tid to (id of t) as text
			set tname to (name of t) as text
			set tidx to (index of t) as text
			set tsel to (selected of t) as text
			repeat with term in terminals of t
				set termid to (id of term) as text
				set termname to (name of term) as text
				set termcwd to (working directory of term) as text
				set out to out & wid & us & wname & us & tid & us & tname & us & tidx & us & tsel & us & termid & us & termname & us & termcwd & rs
			end repeat
		end repeat
	end repeat
end tell
return out
]]

---run an applescript and return its stdout.
---@param script string
---@return string|nil output
---@return string|nil error
function M._run(script)
	if vim.fn.executable('osascript') ~= 1 then
		return nil, 'osascript is not available'
	end

	local ok, output = pcall(vim.fn.system, { 'osascript', '-e', script })
	if not ok then
		return nil, tostring(output)
	end

	if vim.v.shell_error ~= 0 then
		local err = tostring(output):gsub('%s+$', '')
		if err == '' then
			err = 'osascript exited with ' .. tostring(vim.v.shell_error)
		end
		return nil, err
	end

	return output
end

---only macOS ships the AppleScript dictionary used here
---@return boolean
function M.available()
	if vim.fn.has('mac') ~= 1 then
		return false
	end

	if vim.fn.executable('osascript') ~= 1 then
		return false
	end

	if vim.fn.isdirectory('/Applications/Ghostty.app') == 1 then
		return true
	end

	local resources = vim.env.GHOSTTY_RESOURCES_DIR or ''
	return resources ~= ''
end

---@param record string
---@return table|nil
function M._parse(record)
	local f = vim.split(record, us, { plain = true })
	if #f < 9 then
		return nil
	end

	return {
		window_id = f[1],
		window_name = f[2],
		tab_id = f[3],
		tab_title = f[4],
		tab_index = tonumber(f[5]) or 0,
		tab_selected = f[6] == 'true',
		terminal_id = f[7],
		title = f[8],
		cwd = f[9],
	}
end

---list every terminal surface of every ghostty window.
---@return table[]|nil terminals
---@return string|nil error
function M.list_terminals()
	local out, err = M._run(LIST_SCRIPT)
	if not out then
		return nil, err
	end

	local terminals = {}
	for record in out:gmatch('[^' .. rs .. ']+') do
		local terminal = M._parse(record)
		if terminal then
			terminals[#terminals + 1] = terminal
		end
	end

	return terminals
end

---@param value string
---@return string
local function quote(value)
	return '"' .. value:gsub('\\', '\\\\'):gsub('"', '\\"') .. '"'
end

---focus a terminal surface, which also selects its tab and raises its window.
---@param terminal_id string
---@return boolean
---@return string|nil error
function M.focus_terminal(terminal_id)
	if
		type(terminal_id) ~= 'string'
		or not terminal_id:match('^[%w%-%_%.]+$')
	then
		return false, 'invalid terminal id'
	end

	local script = (
		[[
if application "Ghostty" is not running then error "Ghostty is not running"
tell application "Ghostty"
	focus (first terminal whose id is ]]
		.. quote(terminal_id)
		.. [[)
end tell
return "ok"
]]
	)

	local out, err = M._run(script)
	if not out then
		return false, err
	end

	return true
end

return M
