local Picker = require('window-picker.core.picker')
local configurer = require('window-picker.configurer')
local dconfig = require('window-picker.config')
local registry = require('window-picker.core.registry')

local M = {}

---@param custom_config table|nil
---@return number|nil window id or nil
function M.pick_window(custom_config)
	-- drop the abort_info second return value: callers commonly forward the
	-- result straight into nvim_set_current_win(...), where a splatted second
	-- argument would be an error.
	local window = M._pick(custom_config)
	return window
end

---pick any target (nvim window or external pane) and return it. the target is
---already focused as a side effect. callers can dispatch on `target.kind`.
---when the pick is aborted by a source (e.g. herdr zoom hiding nvim), the
---second return value is `{ aborted = true, source = 'herdr' }`.
---@param custom_config table|nil
---@return table|nil target
---@return table|nil abort_info
function M.pick_target(custom_config)
	return M._pick(custom_config, true)
end

---@param custom_config table|nil
---@param return_target boolean|nil
---@return number|table|nil result
---@return table|nil abort_info
function M._pick(custom_config, return_target)
	local config = dconfig

	if custom_config then
		config = vim.tbl_deep_extend('force', config, custom_config)
	end

	config = configurer:new(config).config
	config.return_target = return_target or false

	return Picker:new(config):pick()
end

---register a third party source. `factory` is a table (or module name) with a
---`new(opts, config)` constructor and `available()` / `list(context)` methods.
---@param name string
---@param factory table|string
function M.register_source(name, factory)
	registry.register_source(name, factory)
end

---register a third party renderer. `factory` is a table (or module name) with
---a `new(config)` constructor and `supports(target)` / `draw(entries, ctx)` /
---`clear()` methods.
---@param name string
---@param factory table|string
function M.register_renderer(name, factory)
	registry.register_renderer(name, factory)
end

---arm background prefetch for every source that supports it, so slow sources
---(ghostty's apple-script round trip) have their cache warm before the picker
---is ever opened.
---@param config table
local function arm_source_prefetch(config)
	local sources = config.sources
	if type(sources) ~= 'table' then
		return
	end

	local function arm(name, opts)
		if type(name) ~= 'string' then
			return
		end

		if type(opts) ~= 'table' then
			opts = {}
		end

		if opts.enabled == false then
			return
		end

		local factory = registry.source_factory({ name = name })
		if not factory or type(factory.prefetch) ~= 'function' then
			return
		end

		if type(factory.available) == 'function' then
			local ok, available = pcall(factory.available, factory)
			if not ok or not available then
				return
			end
		end

		pcall(factory.prefetch, factory, opts)
	end

	local islist = vim.islist or vim.tbl_islist

	if islist(sources) then
		for _, value in ipairs(sources) do
			if type(value) == 'string' then
				arm(value, {})
			elseif type(value) == 'table' then
				arm(value.name or value[1], value.opts)
			end
		end

		return
	end

	for name, value in pairs(sources) do
		if value then
			arm(name, value)
		end
	end
end

function M.setup(opts)
	if opts then
		dconfig = vim.tbl_deep_extend('force', dconfig, opts)
	end

	pcall(arm_source_prefetch, dconfig)

	-- Setting highlights at global level
	-- highlight config is deleted so hint classes will only receive the
	-- highlights from config passed to pick_window() function explicitly
	--
	-- Behaviour:
	-- WHEN user wants nether global nor default config, highlights can be
	-- disabled
	--
	-- WHEN global highlights are already set,
	--	IF pick_window() has no highlight config
	--		EXPECTED to use global highlights
	--	IF pick_window({highlights}) has highlight config
	--		EXPECTED to override only the passed highlights ONLY
	--
	-- WHEN global highlights are NOT set
	--	IF pick_window() has no highlight config
	--		EXPECTED to use default config highlights
	--	IF pick_window({highlights}) has highlight config
	--		EXPECTED to override only the passed highlights ONLY

	-- backdrop for the floating list renderer. bg=NONE lets it blend into the
	-- editor instead of painting an opaque NormalFloat rectangle.
	M._create_hl_if_not_exists('WindowPickerWindow', { bg = 'NONE' })

	if not dconfig.highlights.enabled then
		return
	end

	M._create_hl_if_not_exists(
		'WindowPickerStatusLine',
		dconfig.highlights.statusline.focused
	)

	M._create_hl_if_not_exists(
		'WindowPickerStatusLineNC',
		dconfig.highlights.statusline.unfocused
	)

	M._create_hl_if_not_exists(
		'WindowPickerWinBar',
		dconfig.highlights.winbar.focused
	)

	M._create_hl_if_not_exists(
		'WindowPickerWinBarNC',
		dconfig.highlights.winbar.unfocused
	)

	dconfig.highlights = {
		statusline = {
			focused = {},
			unfocused = {},
		},
		winbar = {
			focused = {},
			unfocused = {},
		},
	}
end

function M._create_hl_if_not_exists(name, properties)
	if type(properties) ~= 'table' then
		return
	end

	local hl = vim.api.nvim_get_hl(0, {
		name = name,
	})

	if not vim.tbl_isempty(hl) then
		return
	end

	vim.api.nvim_set_hl(0, name, properties)
end

return M
