# workspace-diagnostics.nvim

Workspace-wide diagnostics for Neovim LSP. Opens all workspace files in the background to trigger LSP diagnostics across your entire project.

## Features

- Async file reading with `vim.uv` (non-blocking)
- Chunked processing to keep UI responsive
- File list caching with configurable TTL
- Early filtering by extension and ignore patterns
- Waits for LSP server to initialize before triggering
- Progress notifications

## Requirements

- Neovim >= 0.10.0
- Git (for `git ls-files`)

## Installation

### lazy.nvim

```lua
{
  'smnatale/workspace-diagnostics.nvim',
  event = 'LspAttach',
  opts = {},
}
```

### packer.nvim

```lua
use {
  'smnatale/workspace-diagnostics.nvim',
  config = function()
    require('workspace-diagnostics').setup()
  end
}
```

## Configuration

```lua
require('workspace-diagnostics').setup({
  -- Trigger workspace diagnostics automatically on LspAttach
  auto_trigger = true,

  -- File list cache TTL in seconds
  cache_ttl = 300,

  -- Number of files to process per async tick
  chunk_size = 10,

  -- Delay in ms between processing chunks
  chunk_delay = 1,

  -- Show start/complete notifications
  notify_progress = true,

  -- Only run workspace diagnostics for these LSP servers
  allowed_lsps = {
    'ts_ls',
    'eslint',
  },

  -- File extensions to include
  allowed_extensions = {
    '.ts',
    '.tsx',
    '.js',
    '.jsx',
    '.mjs',
    '.cjs',
  },

  -- Directory patterns to ignore
  ignore_dirs = {
    '/.yarn/',
    '/node_modules/',
    '/dist/',
    '/build/',
  },
})
```

## Commands

| Command | Description |
|---------|-------------|
| `:WorkspaceDiagnostics` | Trigger workspace diagnostics for attached LSP clients |
| `:WorkspaceDiagnosticsRefresh` | Force refresh (clears cache and re-triggers) |
| `:WorkspaceDiagnosticsStatus` | Show current status (cached files, processing state) |

## API

```lua
local wd = require('workspace-diagnostics')

-- Manually trigger for a specific client
wd.trigger(client, bufnr, force_refresh)

-- Get current status
local status = wd.status()
-- Returns: { cached_files, cache_age, processing, triggered_clients }

-- Clear the file cache
wd.clear_cache()
```

## How it works

1. On `LspAttach`, the plugin waits for the LSP server to fully initialize
2. Collects workspace files using `git ls-files`
3. Filters files by extension and ignore patterns
4. Reads files asynchronously using `vim.uv` (libuv)
5. Sends `textDocument/didOpen` notifications to the LSP server
6. Processes files in chunks to keep the UI responsive

## Performance tuning

For faster processing (may cause micro-stutters):

```lua
{
  chunk_size = 50,  -- Process more files per tick
  chunk_delay = 0,  -- No delay between chunks
}
```

For smoother UI (slower total time):

```lua
{
  chunk_size = 5,   -- Fewer files per tick
  chunk_delay = 10, -- Longer delay between chunks
}
```

## License

MIT
