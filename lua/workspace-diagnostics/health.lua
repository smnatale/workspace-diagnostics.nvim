-- lua/workspace-diagnostics/health.lua
-- Health check for workspace-diagnostics.nvim

local M = {}

function M.check()
	vim.health.start("workspace-diagnostics")

	-- Check Neovim version
	if vim.fn.has("nvim-0.10.0") == 1 then
		vim.health.ok("Neovim >= 0.10.0")
	else
		vim.health.error("Neovim >= 0.10.0 required", {
			"Update Neovim to version 0.10.0 or later",
		})
	end

	-- Check git is available
	local git_version = vim.fn.system("git --version")
	if vim.v.shell_error == 0 then
		vim.health.ok("git is available: " .. vim.trim(git_version))
	else
		vim.health.error("git is not available", {
			"Install git: https://git-scm.com/",
		})
	end

	-- Check if in a git repository
	vim.fn.system("git rev-parse --is-inside-work-tree")
	if vim.v.shell_error == 0 then
		vim.health.ok("Current directory is inside a git repository")
	else
		vim.health.warn("Current directory is not inside a git repository", {
			"workspace-diagnostics requires a git repository to collect files",
			"Run 'git init' to initialize a repository",
		})
	end

	-- Check for attached LSP clients
	local clients = vim.lsp.get_clients()
	if #clients > 0 then
		local client_names = {}
		for _, client in ipairs(clients) do
			table.insert(client_names, client.name)
		end
		vim.health.ok("LSP clients attached: " .. table.concat(client_names, ", "))
	else
		vim.health.info("No LSP clients currently attached")
	end

	-- Check plugin configuration
	local ok, config_module = pcall(require, "workspace-diagnostics.config")
	if ok then
		vim.health.ok("Configuration module loaded")
		vim.health.info("Allowed LSPs: " .. table.concat(config_module.defaults.allowed_lsps, ", "))
		vim.health.info("Allowed extensions: " .. table.concat(config_module.defaults.allowed_extensions, ", "))
	else
		vim.health.error("Failed to load configuration module")
	end
end

return M
