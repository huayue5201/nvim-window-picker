# nvim-window-picker

`hint = 'floating-big-letter'`

https://github.com/s1n7ax/nvim-window-picker/assets/18459807/8a6a57e2-8be0-4385-88a9-f49c6a088627

`hint = 'statusline-winbar'`

https://github.com/s1n7ax/nvim-window-picker/assets/18459807/8d9a790b-cbcb-455d-8d74-97c55b3cc9b0

This plugins prompts the user to pick a window and returns the window id of the
picked window.

## Install

### lazy

```lua
{
    's1n7ax/nvim-window-picker',
    name = 'window-picker',
    event = 'VeryLazy',
    version = '2.*',
    config = function()
        require'window-picker'.setup()
    end,
}
```

### packer

```lua
use {
    's1n7ax/nvim-window-picker',
    tag = 'v2.*',
    config = function()
        require'window-picker'.setup()
    end,
}
```

## How to use

```lua
local picked_window_id = require('window-picker').pick_window()
```

You can put the picked window id to good use

## Configuration

If you want to have custom properties just for one time, you can pass any of
following directly to `pick_window()` function itself to override the default
behaviour.

```lua
require 'window-picker'.setup({
    -- type of hints you want to get
    -- following types are supported
    -- 'statusline-winbar' | 'floating-big-letter' | 'floating-letter'
    -- 'statusline-winbar' draw on 'statusline' if possible, if not 'winbar' will be
    -- 'floating-big-letter' draw big letter on a floating window
    -- 'floating-letter' draw letter on a floating window
    -- used
    hint = 'statusline-winbar',

    -- when you go to window selection mode, status bar will show one of
    -- following letters on them so you can use that letter to select the window
    selection_chars = 'FJDKSLA;CMRUEIWOQP',

    -- This section contains picker specific configurations
    picker_config = {
        -- whether should select window by clicking left mouse button on it
        handle_mouse_click = false,
        statusline_winbar_picker = {
            -- You can change the display string in status bar.
            -- It supports '%' printf style. Such as `return char .. ': %f'` to display
            -- buffer file path. See :h 'stl' for details.
            selection_display = function(char, windowid)
                return '%=' .. char .. '%='
            end,

            -- whether you want to use winbar instead of the statusline
            -- "always" means to always use winbar,
            -- "never" means to never use winbar
            -- "smart" means to use winbar if cmdheight=0 and statusline if cmdheight > 0
            use_winbar = 'never', -- "always" | "never" | "smart"
        },

        floating_big_letter = {
            -- window picker plugin provides bunch of big letter fonts
            -- fonts will be lazy loaded as they are being requested
            -- additionally, user can pass in a table of fonts in to font
            -- property to use instead

            font = 'ansi-shadow', -- ansi-shadow |
        },

        -- configuration for the floating list renderer (also the fallback for
        -- non-nvim targets such as herdr panes)
        floating_list = {
            -- where the list floats. one of 'top-left' | 'top-right',
            -- 'middle-left' | 'middle-right', 'bottom-left' | 'bottom-right',
            -- or 'center'
            position = 'middle-right',

            -- offset from the chosen edge, in cells
            offset_x = 0,
            offset_y = 0,

            -- window border, see :h winborder
            border = 'none', -- 'none' | 'single' | 'rounded' | ...

            -- spaces around the selection char and between it and the info
            label_padding = 1,

            -- highlight group for the selection char
            label_hl = 'DiagnosticVirtualTextHint',

            -- highlight group painted behind the list. 'WindowPickerWindow'
            -- is defined with bg=NONE so the list blends into the editor
            window_bg = 'WindowPickerWindow',
        },
    },

    -- whether to show 'Pick window:' prompt
    show_prompt = true,

    -- prompt message to show to get the user input
    prompt_message = 'Pick window: ',

    -- if you want to manually filter out the windows, pass in a function that
    -- takes two parameters. You should return window ids that should be
    -- included in the selection
    -- EX:-
    -- function(window_ids, filters)
    --    -- folder the window_ids
    --    -- return only the ones you want to include
    --    return {1000, 1001}
    -- end
    filter_func = nil,

    -- following filters are only applied when you are using the default filter
    -- defined by this plugin. If you pass in a function to "filter_func"
    -- property, you are on your own
    filter_rules = {
        -- when there is only one window available to pick from, use that window
        -- without prompting the user to select
        autoselect_one = true,

        -- whether you want to include the window you are currently on to window
        -- selection or not
        include_current_win = false,

        -- whether to include windows marked as unfocusable
        include_unfocusable_windows = false,

        -- filter using buffer options
        bo = {
            -- if the file type is one of following, the window will be ignored
            filetype = { 'NvimTree', 'neo-tree', 'notify', 'snacks_notif' },

            -- if the file type is one of following, the window will be ignored
            buftype = { 'terminal' },
        },

        -- filter using window options
        wo = {},

        -- if the file path contains one of following names, the window
        -- will be ignored
        file_path_contains = {},

        -- if the file name contains one of following names, the window will be
        -- ignored
        file_name_contains = {},
    },

    -- You can pass in the highlight name or a table of content to set as
    -- highlight
    highlights = {
        enabled = true,
        statusline = {
            focused = {
                fg = '#ededed',
                bg = '#e35e4f',
                bold = true,
            },
            unfocused = {
                fg = '#ededed',
                bg = '#44cc41',
                bold = true,
            },
        },
        winbar = {
            focused = {
                fg = '#ededed',
                bg = '#e35e4f',
                bold = true,
            },
            unfocused = {
                fg = '#ededed',
                bg = '#44cc41',
                bold = true,
            },
        },
    },
})
```

```lua
require('window-picker').pick_window({
    hint = 'floating-big-letter'
})
```

## Sources and renderers

Candidates can come from more than one place. A **source** collects targets
and a **renderer** draws the selection hints for the targets it supports.
Targets that no renderer supports are shown in a floating list, so mixing
sources always works out of the box.

Built in sources:

| name | description |
| --- | --- |
| `nvim` | windows of the current nvim instance |
| `herdr` | panes of the [herdr](https://herdr.dev) session the nvim runs in |

Built in renderers:

| name | description |
| --- | --- |
| `nvim_statusline_winbar` | the classic statusline/winbar hints |
| `nvim_floating_letter` | a floating letter per nvim window |
| `nvim_floating_big_letter` | a floating big letter per nvim window |
| `floating_list` | floating list, also the fallback for non-nvim targets |

```lua
require('window-picker').setup({
    -- enable/disable and configure sources. both forms work:
    --   sources = { 'nvim', { name = 'herdr', opts = { scope = 'tab' } } }
    --   sources = { nvim = true, herdr = { scope = 'workspace' } }
    -- herdr scope is one of 'tab' | 'workspace' (default) | 'all'
    -- herdr respect_zoom (scope='tab' only) drops panes hidden by a zoomed tab
    sources = {
        nvim = true,
    },

    -- override the renderers. when omitted it is derived from `hint`.
    -- renderers = { 'nvim_statusline_winbar', 'floating_list' },
})
```

When running inside a herdr pane (`HERDR_ENV=1`) you can pick across panes.
The optional `scope` (`tab` | `workspace` (default) | `all`) and `respect_zoom`
herdr options control which panes are offered. `respect_zoom` is only honored
with `scope = 'tab'`: when the pane's tab is zoomed, panes hidden by that zoom
are dropped from the candidates. If the zoom is on a *different* pane than the
nvim one, the picker does not open at all, since the nvim pane is hidden and
there is nothing visible to switch between. Wider scopes target other tabs /
workspaces, which zoom does not hide, so they ignore `respect_zoom`.
Because `pick_window()` always returns a plain nvim window id (or `nil`), use
`pick_target()` when the caller needs to know which tool was picked:

```lua
-- window id, or nil when a non-nvim target was picked (already focused)
local win = require('window-picker').pick_window({
    sources = { 'nvim', { name = 'herdr', opts = { scope = 'workspace' } } },
})

-- raw target, e.g. { id = 'herdr:wQ:p1', kind = 'herdr', meta = { pane_id = ... } }
-- the second return value is the abort info, e.g. { aborted = true, source = 'herdr' }
local target, abort_info = require('window-picker').pick_target({
    sources = { 'nvim', { name = 'herdr', opts = { scope = 'workspace' } } },
})
if target and target.kind == 'nvim' then
    vim.api.nvim_set_current_win(target.window)
elseif not target and abort_info then
    print('picker aborted by ' .. abort_info.source)
end
```

`pick_window()` returns an nvim window id for nvim targets and `nil` for
external targets (after focusing them). It never returns the abort info, so it
stays safe to splat into `nvim_set_current_win(...)`. `pick_target()` returns
the focused target so callers can dispatch on `target.kind`, plus the abort
info as a second return value when a source vetoed the pick.

### Extending

Register your own source or renderer. Sources need
`available()` and `list(context) -> target[]`; a target is
`{ id, kind, title?, detail?, window?, focus? }` where `focus` is called as
`target:focus()` on selection. A source may also implement
`abort(context) -> boolean`; when it returns true the picker closes without
drawing anything and `pick_target()` reports `{ aborted = true, source = name }`
as its second return value. Renderers need `supports(target)`,
`draw(entries, ctx)` and `clear()`.

```lua
require('window-picker').register_source('my_tool', {
    new = function(self, opts, config) return setmetatable({}, { __index = self }) end,
    available = function() return true end,
    list = function() return { { id = 'x', kind = 'my_tool' } } end,
})
```

Renderers are registered the same way:

```lua
require('window-picker').register_renderer('my_renderer', {
    new = function(config) return setmetatable({}, { __index = renderer }) end,
    supports = function(target) return target.kind == 'my_tool' end,
    draw = function(self, entries, ctx) --[[ render entries ]] end,
    clear = function(self) --[[ undo draw ]] end,
})
```

## Theming

If you just want to define the colors using Neovim Highlights, then it's totally
possible. You can set following highlights manually.

- `WindowPickerStatusLine` (currently focused window statusline highlights)
- `WindowPickerStatusLineNC` (currently unfocused window statusline highlights)
- `WindowPickerWinBar` (currently focused window winbar highlights)
- `WindowPickerWinBarNC` (currently unfocused window winbar highlights)

## Breaking changes in v2.0.0

_Before_: return value from `selection_display` will be wrapped by `'%='` and
`'%='` to fill the empty space of status line or winbar.

_After_: return value of `selection_display` will be passed directly to the
status line or winbar. This allows all the customizations available from
statusline syntax. You can check `:help statusline` for more info.
