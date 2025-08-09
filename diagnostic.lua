local M = {}

local ns = vim.api.nvim_create_namespace 'python-diagnostics'
local root_indicators = { 'setup.cfg', 'pyproject.toml', '.git' }
local lint_egration_path = vim.fn.expand '~/.local/bin/'

---@class LintegrationDiagnostic
---@field column integer
---@field line integer
---@field severity "E" | "W" | "F" | "I" | "H"
---@field message string

---@alias LintegrationDiagnosticJSON {[string]: LintegrationDiagnostic[]}

---@param node TSNode?
---@return TSNode?
local function find_encompassing_ancestor(node)
  if node == nil then
    return nil
  end
  local root = node:tree():root()
  if root == nil then
    return nil
  end
  local descendant = root:child_with_descendant(node)
  while descendant ~= nil and descendant ~= node and descendant:start() ~= node:start() and descendant:end_() ~= node:end_() do
    descendant = descendant:child_with_descendant(node)
  end
  return descendant
end

---@param source string
---@param buffer integer
---@return fun(diagnostic: LintegrationDiagnostic): vim.Diagnostic
function M.lintegration_diagnostic_to_vim_diagnostic(source, buffer)
  ---@param diagnostic LintegrationDiagnostic
  ---@return vim.Diagnostic
  local function _ld_to_vd(diagnostic)
    local severity = vim.diagnostic.severity[diagnostic.severity]
    if severity == nil then
      severity = vim.diagnostic.severity.ERROR
    end
    local column = source == 'mypy' and diagnostic.column or diagnostic.column - 1
    local line = diagnostic.line - 1
    local vim_diagnostic = {
      bufnr = buffer,
      lnum = line,
      col = column,
      severity = severity,
      message = diagnostic.message,
      namespace = ns,
      source = source,
    }
    -- We could use find_encompassing_ancestor, but that gets tricky.
    -- We could use vim.treesitter.get_node, too, but that also has its catches.
    -- For now, let's just avoid working with nodes at all.
    return vim_diagnostic
  end
  return _ld_to_vd
end

---@param json_input table
---@return {result: LintegrationDiagnosticJSON, error: string?}
local function validate_lintegration_json(json_input)
  for file_name, entries in pairs(json_input) do
    if type(file_name) ~= 'string' then
      return { result = {}, error = 'expected top level keys to be strings' }
    end
    for _, entry in ipairs(entries) do
      if type(entry) ~= 'table' then
        return { result = {}, error = 'expected entries to be tables' }
      end
      if entry.column == nil or entry.line == nil or entry.severity == nil or entry.message == nil then
        return { result = {}, error = 'missing expected keys: column, line, severity, message' }
      end
    end
  end
  return { result = json_input, error = nil }--[[@as {result: LintegrationDiagnosticJSON, error: string?}]]
end

---@param bufnr integer
---@return vim.Diagnostic[]
function M.get_flake8_diagnostics(bufnr)
  local bufname = vim.fs.abspath(vim.fn.bufname(bufnr))
  local root = vim.fs.root(bufname, root_indicators)
  local flake8_cli_expr = { vim.fs.joinpath(lint_egration_path, 'flake8.sh') }
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
    vim.notify(string.format('Lintegration: flake8: %s', command_result.stderr), vim.log.levels.ERROR, {})
    return {}
  end
  local parse_result = validate_lintegration_json(vim.json.decode(command_result.stdout))

  if parse_result.error ~= nil then
    vim.notify(string.format('Lintegration: flake8: %s', parse_result.error), vim.log.levels.ERROR, {})
    return {}
  end

  local diagnostic_results = parse_result.result[bufname]
  if diagnostic_results == nil or #diagnostic_results == 0 then
    return {}
  end

  local vim_diagnostics = vim.iter(diagnostic_results):map(M.lintegration_diagnostic_to_vim_diagnostic('flake8', bufnr))
  return vim_diagnostics:totable()
end

---@param bufnr integer
---@return vim.Diagnostic[]
function M.get_mypy_diagnostics(bufnr)
  local bufname = vim.fs.abspath(vim.fn.bufname(bufnr))
  local root = vim.fs.root(bufname, root_indicators)
  -- local setup_cfg = vim.fs.joinpath(root, 'setup.cfg')
  -- local pyproject_toml = vim.fs.joinpath(root, 'pyproject.toml')
  local mypy_cli_expr = { vim.fs.joinpath(lint_egration_path, 'mypy.sh') }
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
    vim.notify('Lintegration: mypy: buffer modified without saving', vim.log.levels.ERROR, {})
    return {}
  end

  local command_result = vim.system(mypy_cli_expr, system_opts):wait()

  if command_result.code ~= 0 or command_result.stdout == nil then
    vim.notify(string.format('Lintegration: mypy: %s', command_result.stderr), vim.log.levels.ERROR, {})
    return {}
  end
  local parse_result = validate_lintegration_json(vim.json.decode(command_result.stdout))

  if parse_result.error ~= nil then
    vim.notify(string.format('Lintegration: mypy: %s', parse_result.error), vim.log.levels.ERROR, {})
    return {}
  end

  local diagnostic_results = parse_result.result[bufname]
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
  vim.diagnostic.set(ns, bufnr, diagnostics, { underline = false })
end

---@param buffer integer | string
function M.clear_diagnostics(buffer)
  local bufnr = vim.fn.bufnr(buffer)
  vim.diagnostic.reset(ns, bufnr)
end

return M
