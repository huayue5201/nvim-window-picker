local M = {}

-- built-in module locations. third parties can either ship a module under
-- their own namespace and reference it with `{ module = '...' }` or register
-- a factory at runtime through `register_source`/`register_renderer`
local SOURCE_MODULES = {
	nvim = 'window-picker.sources.nvim',
	herdr = 'window-picker.sources.herdr',
	ghostty = 'window-picker.sources.ghostty',
}

local RENDERER_MODULES = {
	['nvim_statusline_winbar'] = 'window-picker.renderers.nvim_statusline_winbar',
	['nvim_floating_letter'] = 'window-picker.renderers.nvim_floating_letter',
	['nvim_floating_big_letter'] = 'window-picker.renderers.nvim_floating_big_letter',
	floating_list = 'window-picker.renderers.floating_list',
}

local custom_sources = {}
local custom_renderers = {}

---@param name string
---@param factory table|string
function M.register_source(name, factory)
	custom_sources[name] = factory
end

---@param name string
---@param factory table|string
function M.register_renderer(name, factory)
	custom_renderers[name] = factory
end

local function resolve(factory)
	if type(factory) == 'string' then
		return require(factory)
	end

	return factory
end

---@param spec string|table source spec, either a name or {name=, module=}
---@return table|nil
function M.source_factory(spec)
	local name = type(spec) == 'table' and spec.name or spec
	local module = type(spec) == 'table' and spec.module or nil

	if custom_sources[name] then
		return resolve(custom_sources[name])
	end

	if module then
		return resolve(module)
	end

	if SOURCE_MODULES[name] then
		return require(SOURCE_MODULES[name])
	end

	return nil
end

---@param name string
---@return table|nil
function M.renderer_factory(name)
	if custom_renderers[name] then
		return resolve(custom_renderers[name])
	end

	if RENDERER_MODULES[name] then
		return require(RENDERER_MODULES[name])
	end

	return nil
end

return M
