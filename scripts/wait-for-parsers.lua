-- Block until every parser in nvim-treesitter's merged ensure_installed list
-- is present, then fail if any are still missing.
--
-- Used at image build time. The parser installer is asynchronous, so a fixed
-- `:sleep` races it and can exit before the queue drains. That silently left
-- `hcl` out, and since the `terraform` parser requires `hcl`,
-- `:checkhealth nvim-treesitter` then reported `ERROR terraform(queries)`.
local TIMEOUT_MS = tonumber(vim.env.PARSER_TIMEOUT_MS or "") or 600000
local INTERVAL_MS = 1000

local plugin = require("lazy.core.config").plugins["nvim-treesitter"]
local opts = require("lazy.core.plugin").values(plugin, "opts")
-- Ignore entries nvim-treesitter does not know about (e.g. `jsonc`, which the
-- config lists but the main branch maps to the `json` parser).
local want = require("nvim-treesitter.config").norm_languages(
  opts.ensure_installed or {},
  { unsupported = true }
)
local parsers = require("nvim-treesitter.parsers")

local function installed_set()
  local have = {}
  for _, lang in ipairs(require("nvim-treesitter").get_installed("parsers")) do
    have[lang] = true
  end
  return have
end

local function missing()
  local have = installed_set()
  local miss = {}
  for _, lang in ipairs(want) do
    -- Query-only aliases (ecma, jsx, html_tags) have no parser of their own.
    local p = parsers[lang]
    if p and p.install_info and not have[lang] and not vim.tbl_contains(miss, lang) then
      miss[#miss + 1] = lang
    end
  end
  -- Also require parser dependencies (e.g. terraform -> hcl). Dependencies
  -- without install_info are query-only aliases and need no parser.
  for lang in pairs(have) do
    for _, dep in ipairs((parsers[lang] or {}).requires or {}) do
      local dp = parsers[dep]
      if
        dp
        and dp.install_info
        and not have[dep]
        and not vim.tbl_contains(miss, dep)
      then
        miss[#miss + 1] = dep
      end
    end
  end
  return miss
end

local ok = vim.wait(TIMEOUT_MS, function()
  return #missing() == 0
end, INTERVAL_MS)

if not ok then
  vim.api.nvim_err_writeln(
    "k8s-debug: missing treesitter parsers: " .. table.concat(missing(), ", ")
  )
  vim.cmd("cquit 1")
end

vim.api.nvim_out_write("k8s-debug: all treesitter parsers installed\n")
