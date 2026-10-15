local chars = require('window-picker.core.chars')
local registry = require('window-picker.core.registry')
local util = require('window-picker.util')

local M = {}

local islist = vim.islist or vim.tbl_islist

local HINT_TO_RENDERER = {
	['statusline-winbar'] = 'nvim_statusline_winbar',
	['floating-letter'] = 'nvim_floating_letter',
	['floating-big-letter'] = 'nvim_floating_big_letter',
}

local function notify(msg)
	vim.notify(msg, vim.log.levels.WARN)
end

---normalize `config.sources` into an ordered list of {name=, opts=, module=}
---accepts either a list `{ 'nvim', { name = 'herdr', opts = {...} } }` or a
---map `{ nvim = true, herdr = { scope = 'workspace' } }`. `nvim` is kept first
---in the map form so that nvim windows get the first selection chars.
local function normalize_sources(sources)
	local list = {}

	if type(sources) ~= 'table' then
		return { { name = 'nvim', opts = {} } }
	end

	if islist(sources) then
		for _, value in ipairs(sources) do
			if type(value) == 'string' then
				list[#list + 1] = { name = value, opts = {} }
			elseif type(value) == 'table' then
				list[#list + 1] = {
					name = value.name or value[1],
					opts = value.opts or {},
					module = value.module,
				}
			end
		end

		return list
	end

	local names = vim.tbl_keys(sources)
	table.sort(names, function(a, b)
		if a == 'nvim' then
			return true
		end
		if b == 'nvim' then
			return false
		end
		return a < b
	end)

	for _, name in ipairs(names) do
		local value = sources[name]
		local opts = type(value) == 'table' and value or {}
		if value and opts.enabled ~= false then
			list[#list + 1] = {
				name = name,
				opts = opts,
			}
		end
	end

	return list
end

---resolve the ordered list of renderer names. `config.renderers` wins, then
---the legacy `config.hint` string is mapped onto a built-in renderer.
local function normalize_renderers(config)
	if type(config.renderers) == 'table' and #config.renderers > 0 then
		local list = {}
		for _, value in ipairs(config.renderers) do
			list[#list + 1] = type(value) == 'table'
					and (value.name or value[1])
				or value
		end
		return list
	end

	if type(config.hint) == 'string' then
		return { HINT_TO_RENDERER[config.hint] or config.hint }
	end

	return {}
end

---@param config table normalized plugin config
---@param context table|nil information shared with sources (select_filter, ...)
function M:new(config, context)
	local o = setmetatable({
		config = config,
		context = context or {},
		sources = {},
		renderers = {},
		fallback = nil,
	}, { __index = self })

	for _, spec in ipairs(normalize_sources(config.sources)) do
		local factory = registry.source_factory(spec)
		if factory then
			local ok, source = pcall(function()
				return factory:new(spec.opts, config)
			end)
			if ok and source then
				o.sources[#o.sources + 1] = source
			elseif not ok then
				notify(
					'window-picker: failed to load source '
						.. tostring(spec.name)
						.. ': '
						.. tostring(source)
				)
			end
		else
			notify('window-picker: unknown source ' .. tostring(spec.name))
		end
	end

	if type(config.hint) == 'table' and config.hint.draw then
		local LegacyHint = require('window-picker.renderers.legacy_hint')
		o.renderers[1] = LegacyHint.new(config, config.hint)
	else
		for _, name in ipairs(normalize_renderers(config)) do
			local factory = registry.renderer_factory(name)
			if factory then
				o.renderers[#o.renderers + 1] = factory.new(config)
			else
				notify('window-picker: unknown renderer ' .. tostring(name))
			end
		end
	end

	return o
end

---@return table[] targets
---@return string|nil abort_source source name that aborted, if any
function M:_collect()
	local targets = {}
	local seen = {}

	for _, source in ipairs(self.sources) do
		local ok, available = pcall(source.available, source)
		if ok and available then
			if source.abort then
				local ok_abort, abort =
					pcall(source.abort, source, self.context)
				if ok_abort and abort then
					return targets, source.name or 'unknown'
				end
			end

			local ok_list, list = pcall(source.list, source, self.context)
			if ok_list and list then
				for _, target in ipairs(list) do
					if target.id and not seen[target.id] then
						seen[target.id] = true
						targets[#targets + 1] = target
					end
				end
			end
		end
	end

	return targets, nil
end

---@return table|nil
function M:_fallback_renderer()
	if not self.fallback then
		local factory = registry.renderer_factory('floating_list')
		self.fallback = factory and factory.new(self.config) or nil
	end

	return self.fallback
end

---@param target table
---@return table|nil
function M:_renderer_for(target)
	for _, renderer in ipairs(self.renderers) do
		if renderer:supports(target) then
			return renderer
		end
	end

	return self:_fallback_renderer()
end

---@param entry table
function M._focus(entry)
	local target = entry.target
	if target.focus then
		local ok, focused, err = pcall(target.focus, target)
		if not ok then
			notify('window-picker: focus failed: ' .. tostring(focused))
		elseif focused == false then
			notify('window-picker: focus failed: ' .. tostring(err))
		end
	end
end

---@param entry table
---@param return_target boolean|nil
---@return number|table|nil
function M._result(entry, return_target)
	if return_target then
		return entry.target
	end

	local target = entry.target
	if target.window ~= nil then
		return target.window
	end

	return nil
end

---@return number|table|nil result
---@return table|nil abort_info { aborted = true, source = string }
function M:pick()
	local targets, abort_source = self:_collect()
	if abort_source then
		return nil, { aborted = true, source = abort_source }
	end

	local entries = chars.assign(targets, self.config.chars or {})

	if #entries == 0 then
		return
	end

	if self.config.filter_rules.autoselect_one and #entries == 1 then
		self._focus(entries[1])
		return self._result(entries[1], self.config.return_target)
	end

	local groups, order = {}, {}
	for _, entry in ipairs(entries) do
		local renderer = self:_renderer_for(entry.target)
		if renderer then
			if not groups[renderer] then
				groups[renderer] = {}
				order[#order + 1] = renderer
			end
			groups[renderer][#groups[renderer] + 1] = entry
		end
	end

	local draw_ok, draw_err = pcall(function()
		for _, renderer in ipairs(order) do
			renderer:draw(
				groups[renderer],
				{ context = self.context, config = self.config }
			)
		end
	end)

	if not draw_ok then
		for _, renderer in ipairs(order) do
			pcall(renderer.clear, renderer)
		end
		error(draw_err)
	end

	if self.config.show_prompt then
		print(self.config.prompt_message)
	end

	local char =
		util.get_user_input_char(self.config.picker_config.handle_mouse_click)

	if self.config.show_prompt then
		pcall(util.clear_prompt)
	end

	for _, renderer in ipairs(order) do
		pcall(renderer.clear, renderer)
	end

	if char == '<LeftMouse>' then
		return vim.fn.getmousepos().winid
	end

	local picked = chars.find(entries, char)
	if not picked then
		return
	end

	self._focus(picked)

	return self._result(picked, self.config.return_target)
end

return M
