-- lua/workspace-diagnostics/init.lua
-- Workspace-wide diagnostics for Neovim LSP
-- Opens all workspace files to trigger LSP diagnostics across the entire project

local config_module = require("workspace-diagnostics.config")

local M = {}

-- Module state
local config = nil
local triggered_clients = {}
local file_cache = { files = nil, timestamp = 0 }
local processing_clients = {} -- Per-client processing state (keyed by client.id)

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------

local function is_ignored(path)
	for _, pattern in ipairs(config.ignore_dirs) do
		if path:find(pattern, 1, true) then
			return true
		end
	end
	return false
end

local function has_allowed_extension(path)
	local ext = path:match("(%.[^./]+)$")
	return ext and config._allowed_extensions[ext]
end

--- Collect and cache workspace files (git-based)
---@param force_refresh boolean|nil
---@return string[]
local function collect_files(force_refresh)
	local now = vim.uv.now() / 1000 -- convert ms to seconds

	if not force_refresh and file_cache.files and (now - file_cache.timestamp) < config.cache_ttl then
		return file_cache.files
	end

	local raw_files = vim.fn.systemlist("git ls-files")

	-- Check for git errors (not in a repo, git not installed, etc.)
	if vim.v.shell_error ~= 0 then
		vim.notify(
			"Workspace diagnostics: failed to get file list (not a git repository or git not available)",
			vim.log.levels.WARN
		)
		return {}
	end

	local result = {}

	for _, f in ipairs(raw_files) do
		local path = vim.fn.fnamemodify(f, ":p")
		-- Early filtering: check extension and ignore patterns before adding
		if has_allowed_extension(path) and not is_ignored(path) then
			table.insert(result, path)
		end
	end

	file_cache.files = result
	file_cache.timestamp = now

	return result
end

-------------------------------------------------------------------------------
-- Async file reading with vim.uv
-------------------------------------------------------------------------------

local function read_file_async(path, callback)
	vim.uv.fs_open(path, "r", 438, function(err_open, fd)
		if err_open or not fd then
			callback(nil)
			return
		end

		vim.uv.fs_fstat(fd, function(err_stat, stat)
			if err_stat or not stat then
				vim.uv.fs_close(fd)
				callback(nil)
				return
			end

			vim.uv.fs_read(fd, stat.size, 0, function(err_read, data)
				vim.uv.fs_close(fd)
				if err_read then
					callback(nil)
				else
					callback(data)
				end
			end)
		end)
	end)
end

-------------------------------------------------------------------------------
-- Chunked async processing
-------------------------------------------------------------------------------

local function process_files_async(files, client, bufnr, on_complete)
	local current = vim.api.nvim_buf_get_name(bufnr)
	local total = #files
	local processed = 0
	local idx = 1

	-- Notify start
	if config.notify_progress then
		vim.notify(
			string.format("Workspace diagnostics [%s]: processing %d files...", client.name, total),
			vim.log.levels.INFO
		)
	end

	local function process_chunk()
		if idx > total then
			vim.schedule(function()
				if config.notify_progress then
					vim.notify(
						string.format("Workspace diagnostics [%s]: complete (%d files)", client.name, total),
						vim.log.levels.INFO
					)
				end
				if on_complete then
					on_complete()
				end
			end)
			return
		end

		local chunk_end = math.min(idx + config.chunk_size - 1, total)
		local pending = chunk_end - idx + 1

		for i = idx, chunk_end do
			local path = files[i]

			-- Skip current buffer
			if path == current then
				pending = pending - 1
				processed = processed + 1
				if pending == 0 then
					idx = chunk_end + 1
					vim.defer_fn(process_chunk, config.chunk_delay)
				end
			else
				read_file_async(path, function(content)
					vim.schedule(function()
						if content then
							local ft = vim.filetype.match({ filename = path })
							if ft and vim.tbl_contains(client.config.filetypes or {}, ft) then
								local uri = vim.uri_from_fname(path)

							client:notify("textDocument/didOpen", {
								textDocument = {
									uri = uri,
									languageId = ft,
									version = 0,
									text = content,
								},
							})
							end
						end

						processed = processed + 1
						pending = pending - 1

						if pending == 0 then
							idx = chunk_end + 1
							vim.defer_fn(process_chunk, config.chunk_delay)
						end
					end)
				end)
			end
		end
	end

	process_chunk()
end

-------------------------------------------------------------------------------
-- Main trigger function
-------------------------------------------------------------------------------

local function trigger_workspace_diagnostics(client, bufnr, force_refresh)
	if triggered_clients[client.id] and not force_refresh then
		return
	end

	if not config._allowed_lsps[client.name] then
		return
	end

	if not vim.tbl_get(client.server_capabilities, "textDocumentSync", "openClose") then
		return
	end

	if processing_clients[client.id] then
		vim.notify(
			string.format("Workspace diagnostics already in progress for %s", client.name),
			vim.log.levels.WARN
		)
		return
	end

	triggered_clients[client.id] = true
	processing_clients[client.id] = true

	local files = collect_files(force_refresh)

	process_files_async(files, client, bufnr, function()
		processing_clients[client.id] = nil
	end)
end

-------------------------------------------------------------------------------
-- Wait for LSP initialization
-------------------------------------------------------------------------------

local function wait_for_initialized(client, bufnr, attempts)
	attempts = attempts or 0
	local MAX_ATTEMPTS = 100 -- 10 second timeout (100 * 100ms)

	if attempts > MAX_ATTEMPTS then
		vim.notify(
			string.format("Workspace diagnostics: %s failed to initialize (timeout)", client.name),
			vim.log.levels.WARN
		)
		return
	end

	if client.server_capabilities then
		trigger_workspace_diagnostics(client, bufnr, false)
	else
		vim.defer_fn(function()
			-- Re-check client is still valid
			if vim.lsp.get_client_by_id(client.id) then
				wait_for_initialized(client, bufnr, attempts + 1)
			end
		end, 100)
	end
end

-------------------------------------------------------------------------------
-- Public API
-------------------------------------------------------------------------------

--- Setup the plugin with user configuration
---@param user_config table|nil
function M.setup(user_config)
	config = config_module.merge(user_config)

	-- Create user commands
	vim.api.nvim_create_user_command("WorkspaceDiagnostics", function()
		local bufnr = vim.api.nvim_get_current_buf()
		for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
			trigger_workspace_diagnostics(client, bufnr, false)
		end
	end, { desc = "Trigger workspace diagnostics for attached LSP clients" })

	vim.api.nvim_create_user_command("WorkspaceDiagnosticsRefresh", function()
		-- Reset triggered state to allow re-triggering
		triggered_clients = {}
		processing_clients = {}

		local bufnr = vim.api.nvim_get_current_buf()
		for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
			trigger_workspace_diagnostics(client, bufnr, true)
		end
	end, { desc = "Force refresh workspace diagnostics (clears cache)" })

	vim.api.nvim_create_user_command("WorkspaceDiagnosticsStatus", function()
		local files = file_cache.files
		local age = file_cache.timestamp > 0 and (vim.uv.now() / 1000 - file_cache.timestamp) or 0

		-- Build list of processing client names
		local processing_names = {}
		for client_id, _ in pairs(processing_clients) do
			local client = vim.lsp.get_client_by_id(client_id)
			if client then
				table.insert(processing_names, client.name)
			end
		end

		vim.notify(
			string.format(
				"Workspace diagnostics status:\n"
					.. "  Cached files: %d\n"
					.. "  Cache age: %.0fs\n"
					.. "  Processing: %s\n"
					.. "  Triggered clients: %d",
				files and #files or 0,
				age,
				#processing_names > 0 and table.concat(processing_names, ", ") or "none",
				vim.tbl_count(triggered_clients)
			),
			vim.log.levels.INFO
		)
	end, { desc = "Show workspace diagnostics status" })

	-- Auto-trigger on LSP attach
	if config.auto_trigger then
		vim.api.nvim_create_autocmd("LspAttach", {
			group = vim.api.nvim_create_augroup("WorkspaceDiagnostics", { clear = true }),
			callback = function(args)
				local client = vim.lsp.get_client_by_id(args.data.client_id)
				if client then
					wait_for_initialized(client, args.buf, 0)
				end
			end,
		})
	end
end

--- Manually trigger workspace diagnostics for a specific client
---@param client table LSP client
---@param bufnr number Buffer number
---@param force_refresh boolean|nil Force refresh the file cache
function M.trigger(client, bufnr, force_refresh)
	if not config then
		vim.notify("workspace-diagnostics: call setup() first", vim.log.levels.ERROR)
		return
	end
	trigger_workspace_diagnostics(client, bufnr, force_refresh or false)
end

--- Get current status
---@return table
function M.status()
	return {
		cached_files = file_cache.files and #file_cache.files or 0,
		cache_age = file_cache.timestamp > 0 and (vim.uv.now() / 1000 - file_cache.timestamp) or 0,
		processing_clients = vim.tbl_keys(processing_clients),
		triggered_clients = vim.tbl_count(triggered_clients),
	}
end

--- Clear the file cache and reset state
function M.clear_cache()
	file_cache = { files = nil, timestamp = 0 }
	triggered_clients = {}
	processing_clients = {}
end

return M
