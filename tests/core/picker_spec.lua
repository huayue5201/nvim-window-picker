local chars = require('window-picker.core.chars')
local core_picker = require('window-picker.core.picker')
local registry = require('window-picker.core.registry')
local util = require('window-picker.util')

local function base_config(overrides)
	return vim.tbl_deep_extend('force', {
		sources = {},
		renderers = {},
		chars = { 'a', 'b', 'c' },
		show_prompt = false,
		filter_rules = { autoselect_one = false },
		picker_config = { handle_mouse_click = false },
	}, overrides or {})
end

describe('core_picker::', function()
	it('assigns chars in order and falls back to numbers', function()
		local entries = chars.assign(
			{ { id = 1 }, { id = 2 }, { id = 3 }, { id = 4 } },
			{ 'a', 'b' }
		)

		assert.equals('a', entries[1].char)
		assert.equals('b', entries[2].char)
		assert.equals('3', entries[3].char)
		assert.equals('4', entries[4].char)
	end)

	it('finds an entry case insensitively', function()
		local entries = chars.assign({ { id = 1 } }, { 'F' })

		assert.equals(entries[1], chars.find(entries, 'f'))
		assert.is_nil(chars.find(entries, 'z'))
	end)

	it('collects targets from all available sources', function()
		registry.register_source('test_a', {
			new = function(self)
				return setmetatable({}, { __index = self })
			end,
			available = function()
				return true
			end,
			list = function()
				return { { id = 'a1', kind = 'a' } }
			end,
		})
		registry.register_source('test_b', {
			new = function(self)
				return setmetatable({}, { __index = self })
			end,
			available = function()
				return false
			end,
			list = function()
				return { { id = 'b1', kind = 'b' } }
			end,
		})

		local picker = core_picker:new(
			base_config({ sources = { test_a = true, test_b = true } })
		)

		local targets = picker:_collect()

		assert.equals(1, #targets)
		assert.equals('a1', targets[1].id)
	end)

	it('groups targets by renderer and returns the picked target', function()
		local drawn = {}
		registry.register_source('test_source', {
			new = function(self)
				return setmetatable({}, { __index = self })
			end,
			available = function()
				return true
			end,
			list = function()
				return {
					{ id = 'nvim', kind = 'nvim', window = 1000 },
				}
			end,
		})
		registry.register_renderer('test_nvim', {
			new = function()
				return {
					supports = function(_, target)
						return target.kind == 'nvim'
					end,
					draw = function(_, entries)
						drawn.nvim = entries
					end,
					clear = function() end,
				}
			end,
		})
		registry.register_renderer('test_herdr', {
			new = function()
				return {
					supports = function(_, target)
						return target.kind == 'herdr'
					end,
					draw = function(_, entries)
						drawn.herdr = entries
					end,
					clear = function() end,
				}
			end,
		})

		local focused
		registry.register_source('test_focus', {
			new = function(self)
				return setmetatable({}, { __index = self })
			end,
			available = function()
				return true
			end,
			list = function()
				return {
					{
						id = 'pane',
						kind = 'herdr',
						focus = function(target)
							focused = target.id
						end,
					},
				}
			end,
		})

		util.get_user_input_char = function()
			return 'b'
		end

		local picker = core_picker:new(base_config({
			sources = { 'test_source', 'test_focus' },
			renderers = { 'test_nvim', 'test_herdr' },
		}))

		local result = picker:pick()

		assert.equals(1, #drawn.nvim)
		assert.equals(1, #drawn.herdr)
		assert.equals('pane', focused)
		-- non-nvim target with no `window` has no window id to return
		assert.is_nil(result)
	end)

	it('returns the raw target when return_target is set', function()
		util.get_user_input_char = function()
			return 'a'
		end

		local picker = core_picker:new(base_config({
			sources = { 'test_focus' },
			renderers = { 'test_nvim', 'test_herdr' },
			return_target = true,
		}))

		local result = picker:pick()

		assert.equals('table', type(result))
		assert.equals('pane', result.id)
		assert.equals('herdr', result.kind)
	end)

	it('autoselects the only target when enabled', function()
		registry.register_source('single', {
			new = function(self)
				return setmetatable({}, { __index = self })
			end,
			available = function()
				return true
			end,
			list = function()
				return { { id = 'only', kind = 'nvim', window = 7 } }
			end,
		})

		local picker = core_picker:new(base_config({
			sources = { single = true },
			filter_rules = { autoselect_one = true },
		}))

		assert.equals(7, picker:pick())
	end)

	it('returns nil without drawing when a source aborts', function()
		registry.register_source('aborter', {
			name = 'aborter',
			new = function(self)
				return setmetatable({}, { __index = self })
			end,
			available = function()
				return true
			end,
			abort = function()
				return true
			end,
			list = function()
				error('list should not run after abort')
			end,
		})

		local picker = core_picker:new(base_config({
			sources = { aborter = true },
			filter_rules = { autoselect_one = true },
		}))

		local result, abort_info = picker:pick()

		assert.is_nil(result)
		assert.is_true(abort_info.aborted)
		assert.equals('aborter', abort_info.source)
	end)
end)
