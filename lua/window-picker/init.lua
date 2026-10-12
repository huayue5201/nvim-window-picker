local Picker = require('window-picker.core.picker')
local configurer = require('window-picker.configurer')
local dconfig = require('window-picker.config')
local registry = require('window-picker.core.registry')

local M = {}

---@param custom_config table|nil
---@return number|nil window id or nil
function M.pick_window(custom_config)
	return M._pick(custom_config)
end

---pick any target (nvim window or external pane) and return it. the target is
---already focused as a side effect. callers can dispatch on `target.kind`.
---@param custom_config table|nil
---@return table|nil target
function M.pick_target(custom_config)
	return M._pick(custom_config, true)
end

---@param custom_config table|nil
---@param return_target boolean|nil
---@return number|table|nil
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

function M.setup(opts)
	if opts then
		dconfig = vim.tbl_deep_extend('force', dconfig, opts)
	end

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
