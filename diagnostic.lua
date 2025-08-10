local M = {}

local ns = vim.api.nvim_create_namespace 'python-diagnostics'
local root_indicators = { 'setup.cfg', 'pyproject.toml', '.git' }
local lint_egration_path = vim.fn.expand '~/.local/bin/'

local L = {}
---@param source string
---@param message string
function L.err(source, message)
  vim.notify(string.format('lintegration: %s: %s', source, message), vim.log.levels.ERROR, {})
end

---@class LintegrationDiagnostic
---@field col integer
---@field lnum integer
---@field severity vim.diagnostic.Severity
---@field message string
---@field source string

---@alias LintegrationDiagnosticJSON {[string]: LintegrationDiagnostic[]}

---@param source string
---@param buffer integer
---@return fun(diagnostic: LintegrationDiagnostic): vim.Diagnostic
function M.lintegration_diagnostic_to_vim_diagnostic(source, buffer)
  ---@param diagnostic LintegrationDiagnostic
  ---@return vim.Diagnostic
  local function _ld_to_vd(diagnostic)
    local vim_diagnostic = {
      bufnr = buffer,
      lnum = diagnostic.lnum,
      col = diagnostic.col,
      severity = diagnostic.severity,
      message = diagnostic.message,
      namespace = ns,
      source = diagnostic.source,
    }
    -- We could use find_encompassing_ancestor, but that gets tricky.
    -- We could use vim.treesitter.get_node, too, but that also has its catches.
    -- For now, let's just avoid working with nodes at all.
    return vim_diagnostic
  end
  return _ld_to_vd
end

---@param bufnr integer
---@return vim.Diagnostic[]
function M.get_flake8_diagnostics(bufnr)
  local function err(str)
    L.err('flake8', str)
  end
  local bufname = vim.fs.abspath(vim.fn.bufname(bufnr))
  local root = vim.fs.root(bufname, root_indicators)
  local flake8_cli_expr = { vim.fs.joinpath(lint_egration_path, 'flake8_for_nvim.sh') }
  local system_opts = { text = true }

  if root ~= nil then
    system_opts.cwd = root
    -- It's safe to assume that vim.fs.relpath(root, bufname) is not nil, because root is:
    -- 1. not nil
    -- 2. derived from bufname
    bufname = vim.fs.relpath(root, bufname) --[[@as string]]
  end

  if not vim.bo.modified then
    table.insert(flake8_cli_expr, bufname)
  else
    table.insert(flake8_cli_expr, string.format('--stdin-display-name=%s', bufname))
    system_opts.stdin = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), '\n')
  end

  local command_result = vim.system(flake8_cli_expr, system_opts):wait()

  if command_result.code ~= 0 or command_result.stdout == nil then
    err(command_result.stderr)
    return {}
  end

  ---@type boolean, LintegrationDiagnosticJSON
  local ok, parse_result = pcall(vim.json.decode, command_result.stdout)

  if not ok then
    err(parse_result)
    return {}
  end

  local diagnostic_results = parse_result[bufname]
  if diagnostic_results == nil or #diagnostic_results == 0 then
    return {}
  end

  local vim_diagnostics = vim.iter(diagnostic_results):map(M.lintegration_diagnostic_to_vim_diagnostic('flake8', bufnr))
  return vim_diagnostics:totable()
end

---@param bufnr integer
---@return vim.Diagnostic[]
function M.get_mypy_diagnostics(bufnr)
  local function err(str)
    L.err('mypy', str)
  end
  local bufname = vim.fs.abspath(vim.fn.bufname(bufnr))
  local root = vim.fs.root(bufname, root_indicators)
  local mypy_cli_expr = { vim.fs.joinpath(lint_egration_path, 'mypy_for_nvim.sh') }
  local system_opts = { text = true }
  if root ~= nil then
    system_opts.cwd = root
    -- It's safe to assume that vim.fs.relpath(root, bufname) is not nil, because root is:
    -- 1. not nil
    -- 2. derived from bufname
    bufname = vim.fs.relpath(root, bufname) --[[@as string]]
  end

  if not vim.bo.modified then
    table.insert(mypy_cli_expr, bufname)
  else
    err 'buffer modified without saving'
    return {}
  end

  local command_result = vim.system(mypy_cli_expr, system_opts):wait()

  if command_result.code ~= 0 or command_result.stdout == nil then
    err(command_result.stderr)
    return {}
  end

  ---@type boolean, LintegrationDiagnosticJSON
  local ok, parse_result = pcall(vim.json.decode, command_result.stdout)

  if not ok then
    err(parse_result)
    return {}
  end

  local diagnostic_results = parse_result[bufname]
  if diagnostic_results == nil or #diagnostic_results == 0 then
    return {}
  end
  local vim_diagnostics = vim.iter(diagnostic_results):map(M.lintegration_diagnostic_to_vim_diagnostic('mypy', bufnr))
  return vim_diagnostics:totable()
end

---@param buffer integer | string
function M.set_diagnostics(buffer)
  local bufnr = vim.fn.bufnr(buffer)

  local diagnostics = {}
  local flake8_diagnostics = M.get_flake8_diagnostics(bufnr)
  vim.list_extend(diagnostics, flake8_diagnostics)
  local mypy_diagnostics = M.get_mypy_diagnostics(bufnr)
  vim.list_extend(diagnostics, mypy_diagnostics)
  vim.diagnostic.set(ns, bufnr, diagnostics, {})
end

---@param buffer integer | string
function M.clear_diagnostics(buffer)
  local bufnr = vim.fn.bufnr(buffer)
  vim.diagnostic.reset(ns, bufnr)
end

return M
