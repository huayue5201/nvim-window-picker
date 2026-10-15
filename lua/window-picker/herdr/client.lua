local M = {}

local uv = vim.uv or vim.loop
local counter = 0

---@return string
function M.socket_path()
	if vim.env.HERDR_SOCKET_PATH and vim.env.HERDR_SOCKET_PATH ~= '' then
		return vim.env.HERDR_SOCKET_PATH
	end

	return vim.fn.expand('~/.config/herdr/herdr.sock')
end

---send a single request over the herdr unix socket and wait for its reply.
---the herdr protocol is newline delimited JSON, one request per line.
---@param method string
---@param params table|nil
---@param timeout integer|nil milliseconds
---@return table|nil result
---@return string|nil error
function M.call(method, params, timeout)
	if not uv then
		return nil, 'vim.uv is not available'
	end

	local path = M.socket_path()
	local ok_json, payload = pcall(vim.json.encode, {
		id = 'window-picker:' .. tostring(counter),
		method = method,
		params = params or {},
	})
	counter = counter + 1

	if not ok_json then
		return nil, 'could not encode request: ' .. tostring(payload)
	end

	local pipe = uv.new_pipe(false)
	if not pipe then
		return nil, 'could not create pipe'
	end

	local buffer = ''
	local done = false
	local result, err = nil, nil

	local function finish()
		done = true
	end

	pipe:connect(path, function(connect_err)
		if connect_err then
			err = tostring(connect_err)
			finish()
			return
		end

		pipe:write(payload .. '\n', function(write_err)
			if write_err then
				err = tostring(write_err)
				finish()
			end
		end)
	end)

	pipe:read_start(function(read_err, data)
		if read_err then
			err = tostring(read_err)
			finish()
			return
		end

		if not data then
			return
		end

		buffer = buffer .. data
		local newline = buffer:find('\n', 1, true)
		if not newline then
			return
		end

		local line = buffer:sub(1, newline - 1)
		local ok_decode, decoded = pcall(vim.json.decode, line)
		if not ok_decode then
			err = 'invalid response: ' .. tostring(decoded)
		elseif decoded.error then
			err = type(decoded.error) == 'table'
					and (decoded.error.message or vim.inspect(decoded.error))
				or tostring(decoded.error)
		else
			result = decoded.result
		end

		finish()
	end)

	vim.wait(timeout or 1500, function()
		return done
	end, 5)

	if not done then
		err = err or ('herdr request timed out: ' .. method)
	end

	pcall(function()
		pipe:read_stop()
	end)
	pcall(function()
		pipe:close()
	end)

	return result, err
end

---@return table[]|nil panes
---@return string|nil error
function M.pane_list(opts)
	local result, err = M.call('pane.list', opts or {})
	if not result then
		return nil, err
	end

	return result.panes
end

---@param opts table|nil { pane_id = string }
---@return table|nil layout PaneLayoutSnapshot of the pane's tab
---@return string|nil error
function M.pane_layout(opts)
	local result, err = M.call('pane.layout', opts or {})
	if not result then
		return nil, err
	end

	return result.layout
end

---@param pane_id string
---@return boolean
---@return string|nil error
function M.pane_focus(pane_id)
	local result, err = M.call('pane.focus', { pane_id = pane_id })
	if result == nil then
		return false, err
	end

	return true
end

return M
