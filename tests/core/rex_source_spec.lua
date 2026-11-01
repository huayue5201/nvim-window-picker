local rex = require('window-picker.sources.rex')
local client = require('window-picker.rex.client')

local OWN = 'block:own'

---@param zoomed string|nil
local function view(zoomed)
	return {
		active_window_id = 'window:a',
		windows = {
			{
				window_id = 'window:a',
				label = 'Window a',
				focused_block_id = OWN,
				zoomed_block_id = zoomed,
				layers = {
					{
						kind = 'tiled',
						blocks = {
							{ block_id = OWN, label = 'shell' },
							{ block_id = 'block:a2', label = 'shell' },
						},
					},
				},
			},
			{
				window_id = 'window:b',
				label = 'Window b',
				focused_block_id = 'block:b1',
				layers = {
					{
						kind = 'tiled',
						blocks = {
							{ block_id = 'block:b1', label = 'logs' },
						},
					},
				},
			},
		},
	}
end

describe('rex source::', function()
	local originals = {}
	local current_view = view(nil)

	before_each(function()
		for _, name in ipairs({
			'available',
			'view',
			'cached_view',
			'block_id',
			'cached_process',
			'focus_block',
			'refresh',
		}) do
			originals[name] = client[name]
		end

		current_view = view(nil)
		client.available = function()
			return true
		end
		client.view = function()
			return current_view
		end
		client.cached_view = function()
			return current_view
		end
		client.block_id = function()
			return OWN
		end
		client.cached_process = function()
			return nil
		end
		client.focus_block = function()
			return true
		end
		client.refresh = function() end
	end)

	after_each(function()
		for name, value in pairs(originals) do
			client[name] = value
		end
	end)

	it(
		'defaults to the window scope and honors respect_zoom there only',
		function()
			local default = rex:new({}, {})
			assert.equals('window', default.scope)
			assert.is_true(default.respect_zoom)

			assert.is_false(rex:new({ respect_zoom = false }, {}).respect_zoom)
			assert.is_false(
				rex:new({ scope = 'session', respect_zoom = true }, {}).respect_zoom
			)
		end
	)

	it('lists only sibling blocks of the current window by default', function()
		local targets = rex:new({}, {}):list()

		assert.equals(1, #targets)
		assert.equals('rex:block:a2', targets[1].id)
		assert.equals('rex', targets[1].kind)
	end)

	it('lists other windows with scope = session, nearest first', function()
		local targets = rex:new({ scope = 'session' }, {}):list()

		assert.equals(2, #targets)
		assert.equals('rex:block:a2', targets[1].id)
		assert.equals('rex:block:b1', targets[2].id)
		-- other windows are marked with their label
		assert.equals('Window b', targets[2].detail)
	end)

	it(
		'hides blocks behind a zoomed sibling when respect_zoom is on',
		function()
			current_view = view('block:a2')

			local targets = rex:new({ scope = 'session' }, {}):list()

			assert.equals(2, #targets)
			assert.equals('rex:block:a2', targets[1].id)
			assert.equals('rex:block:b1', targets[2].id)
		end
	)

	it('titles blocks by their foreground program when known', function()
		client.cached_process = function()
			return {
				foreground = { name = 'nvim', cwd = '/tmp/project' },
			}
		end

		local targets = rex:new({}, {}):list()

		assert.equals('nvim', targets[1].title)
		assert.equals('/tmp/project', targets[1].detail)
	end)

	it('falls back to the block label without terminal info', function()
		current_view = view(nil)
		current_view.windows[1].layers[1].blocks[2].label = 'logs'

		local targets = rex:new({}, {}):list()

		assert.equals('logs', targets[1].title)
		assert.is_nil(targets[1].detail)
	end)

	describe('abort::', function()
		it('never aborts when respect_zoom is off', function()
			current_view = view('block:a2')

			assert.is_false(rex:new({ respect_zoom = false }, {}):abort())
			assert.is_false(rex:new({ scope = 'session' }, {}):abort())
		end)

		it('aborts when nvim is hidden behind another block zoom', function()
			current_view = view('block:a2')

			assert.is_true(rex:new({}, {}):abort())
		end)

		it('does not abort when nvim is the zoomed block', function()
			current_view = view(OWN)

			assert.is_false(rex:new({}, {}):abort())
		end)

		it('does not abort without a zoom', function()
			current_view = view(nil)

			assert.is_false(rex:new({}, {}):abort())
		end)
	end)
end)
