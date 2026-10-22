local M = {}

-- Ghostty (macOS) has no IPC socket, but it ships an AppleScript dictionary
-- (Ghostty.sdef) that can enumerate windows/tabs/terminals and focus them.
--
-- Every query is a full round trip through AppleScript: process startup
-- (~70ms) plus one IPC round trip per property read. Listing a single window
-- with a handful of tabs easily costs 200-400ms, which is way too slow to do
-- inline on every pick. Everything here is therefore cached and refreshed in
-- the background, and a single script fetches the terminal list together with
-- the "current surface" anchor.

local uv = vim.uv or vim.loop

local rs = string.char(30) -- record separator
local us = string.char(31) -- unit separator

local HEADER = [[
set rs to (ASCII character 30)
set us to (ASCII character 31)
if application "Ghostty" is not running then return ""
set out to ""
]]

-- only the front window's selected tab: cheap, and it is exactly the candidate
-- set of scope = 'tab'. also reported under the 'cur' marker when ghostty is
-- frontmost (the keystroke that opened the picker came from there).
local TAB_SCRIPT = HEADER
	.. [[
tell application "Ghostty"
	try
		if not (frontmost) then return ""
		set fw to front window
		set ft to selected tab of fw
		set fterm to focused terminal of ft
		set wid to (id of fw) as text
		set wname to (name of fw) as text
		set tid to (id of ft) as text
		set tname to (name of ft) as text
		set out to out & "cur" & us & wid & us & tid & us & ((id of fterm) as text) & rs
		repeat with term in terminals of ft
			set termid to (id of term) as text
			set termname to (name of term) as text
			set termcwd to (working directory of term) as text
			set out to out & wid & us & wname & us & tid & us & tname & us & "1" & us & "true" & us & termid & us & termname & us & termcwd & rs
		end repeat
	on error
	end try
end tell
return out
]]

-- every terminal of every window, plus the current surface marker. used by
-- scope = 'window' / 'all', and as a fallback when ghostty is not frontmost
-- (the anchor is then matched on cwd and terminal title).
local ALL_SCRIPT = HEADER
	.. [[
tell application "Ghostty"
	try
		if frontmost then
			set fw to front window
			set ft to selected tab of fw
			set fterm to focused terminal of ft
			set out to out & "cur" & us & ((id of fw) as text) & us & ((id of ft) as text) & us & ((id of fterm) as text) & rs
		end if
	end try
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

-- how long a cached snapshot may be reused before pick() pays for a fresh
-- (blocking) read. the cache is refreshed in the background by prefetch events
-- and after every pick, so this is only the safety net for a long idle period.
M.cache_ttl = 5000

-- minimum gap between two background refreshes of the same scope
M.refresh_interval = 500

-- refresh only when the cached snapshot is at least this old. prefetch events
-- (CursorHold and friends) fire a lot; the snapshot only changes when the user
-- opens/closes a ghostty tab or window, so a couple of seconds is plenty.
M.prefetch_age = 2000

---@return number monotonic milliseconds
local function now_ms()
	if uv then
		return uv.hrtime() / 1e6
	end

	return vim.fn.reltimefloat(vim.fn.reltime()) * 1000
end

local cache = {} -- scope key -> { terminals, current, at }
local inflight = {} -- scope key -> job id
local last_refresh = {} -- scope key -> ms

---@param scope string|nil
---@return 'tab'|'all'
local function scope_key(scope)
	if scope == 'tab' then
		return 'tab'
	end

	return 'all'
end

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

---parse the combined output of TAB_SCRIPT / ALL_SCRIPT.
---@param out string|nil
---@return table[] terminals
---@return table|nil current { window_id, tab_id, terminal_id }
function M._parse_snapshot(out)
	local terminals = {}
	local current = nil

	if not out or out == '' then
		return terminals, current
	end

	for record in out:gmatch('[^' .. rs .. ']+') do
		local fields = vim.split(record, us, { plain = true })
		if #fields == 4 and fields[1] == 'cur' then
			if fields[2] ~= '' and fields[4] ~= '' then
				current = {
					window_id = fields[2],
					tab_id = fields[3],
					terminal_id = fields[4],
				}
			end
		else
			local terminal = M._parse(record)
			if terminal then
				terminals[#terminals + 1] = terminal
			end
		end
	end

	return terminals, current
end

---@param key 'tab'|'all'
---@return string
local function script_for(key)
	return key == 'tab' and TAB_SCRIPT or ALL_SCRIPT
end

---blocking read, updates the cache.
---@param opts table|nil { scope = 'tab'|'window'|'all', ttl = number }
---@return table[]|nil terminals
---@return string|nil error
local function fetch_sync(opts)
	local key = scope_key(opts and opts.scope)
	local out, err = M._run(script_for(key))
	if not out then
		return nil, err
	end

	local terminals, current = M._parse_snapshot(out)

	-- the tab script cannot anchor nvim's surface when ghostty is not
	-- frontmost; fall back to the full snapshot, which also matches on cwd.
	if key == 'tab' and not current then
		local fallback, fallback_err =
			fetch_sync({ scope = 'all', ttl = opts and opts.ttl })
		if not fallback then
			return nil, fallback_err
		end

		-- the full snapshot is a superset of the tab one, and scope filtering
		-- happens in the source, so it is safe to serve tab reads from it.
		cache[key] = cache['all']

		return cache[key].terminals
	end

	cache[key] = { terminals = terminals, current = current, at = now_ms() }

	return terminals
end

---refresh one scope in the background. debounced, and a no-op while a refresh
---of the same scope is already running.
---@param opts table|nil { scope = 'tab'|'window'|'all', min_age = number }
---@return boolean started
function M.refresh(opts)
	if not uv then
		return false
	end

	local key = scope_key(opts and opts.scope)
	if inflight[key] then
		return false
	end

	local started_at = now_ms()
	local entry = cache[key]
	local all = cache['all']
	if all and (not entry or all.at > entry.at) then
		-- a full snapshot is a superset of the tab one and is always newer
		-- information than nothing at all
		entry = all
	end
	if
		opts
		and opts.min_age
		and entry
		and started_at - entry.at < opts.min_age
	then
		return false
	end

	if
		last_refresh[key]
		and started_at - last_refresh[key] < M.refresh_interval
	then
		return false
	end
	last_refresh[key] = started_at

	local lines = {}
	local function clear()
		inflight[key] = nil
	end

	local ok, job = pcall(
		vim.fn.jobstart,
		{ 'osascript', '-e', script_for(key) },
		{
			stdout_buffered = true,
			stderr_buffered = true,
			on_stdout = function(_, data)
				lines = data or {}
			end,
			on_exit = function(_, code)
				clear()
				if code ~= 0 then
					return
				end

				local terminals, current =
					M._parse_snapshot(table.concat(lines, '\n'))

				if key == 'tab' and not current then
					-- no anchor from the tab script (ghostty not frontmost): take
					-- the full snapshot so cwd/title matching has something to
					-- work with.
					M.refresh({ scope = 'all', min_age = M.prefetch_age })
					return
				end

				cache[key] =
					{ terminals = terminals, current = current, at = now_ms() }
			end,
		}
	)

	if not ok or job <= 0 then
		clear()
		return false
	end

	inflight[key] = job

	return true
end

---cached snapshot, refreshed in the background. blocks only when there is no
---usable cache entry (first pick, or after cache_ttl of inactivity).
---@param opts table|nil { scope = 'tab'|'window'|'all', ttl = number }
---@return table[]|nil terminals
---@return table|nil current
---@return string|nil error
function M.snapshot(opts)
	opts = opts or {}
	local key = scope_key(opts.scope)
	local ttl = opts.ttl or M.cache_ttl
	local entry = cache[key]

	-- a fresh full snapshot is a superset of the tab one (scope filtering
	-- happens in the source), so reuse it instead of paying for a tab scan.
	if not entry and key == 'tab' then
		local all = cache['all']
		if all and now_ms() - all.at <= ttl then
			entry = all
		end
	end

	if entry and now_ms() - entry.at <= ttl then
		-- keep the cache warm for the next pick while the user picks a char
		M.refresh({ scope = opts.scope, min_age = M.prefetch_age })
		return entry.terminals, entry.current
	end

	local terminals, err = fetch_sync(opts)
	if not terminals then
		return nil, nil, err
	end

	entry = cache[key]
	M.refresh({ scope = opts.scope })

	return terminals, entry and entry.current or nil
end

---drop every cached snapshot (used by tests).
function M._clear_cache()
	cache = {}
	inflight = {}
	last_refresh = {}
end

---@param opts table|nil { scope = 'tab'|'window'|'all', ttl = number }
---@return table[]|nil terminals
---@return string|nil error
function M.list_terminals(opts)
	local terminals, _, err = M.snapshot(opts)
	if not terminals then
		return nil, err
	end

	return terminals
end

---the terminal surface nvim most likely runs in, or nil when ghostty is not the
---frontmost app or the script fails.
---@param opts table|nil { scope = 'tab'|'window'|'all', ttl = number }
---@return table|nil { window_id, tab_id, terminal_id }
function M.current_surface(opts)
	local _, current = M.snapshot(opts)
	return current
end

---@param value string
---@return string
local function quote(value)
	return '"' .. value:gsub('\\', '\\\\'):gsub('"', '\\"') .. '"'
end

---focus a terminal surface, which also selects its tab and raises its window.
---fire and forget: ghostty is the app that changes, nvim cannot observe the
---result anyway and waiting for the round trip only delays the jump.
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

	local ok, job = pcall(vim.fn.jobstart, { 'osascript', '-e', script }, {
		stdout_buffered = true,
		stderr_buffered = true,
	})

	if not ok or job <= 0 then
		-- fall back to the blocking path so the pick is not silently lost
		local out, err = M._run(script)
		if not out then
			return false, err
		end
	end

	return true
end

return M
