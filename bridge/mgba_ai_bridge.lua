-- BizHawk Lua (tested flavor). If using mGBA: confirm LuaSocket availability; otherwise we can switch to a python sidecar.
-- Requires LuaSocket:
--   In BizHawk, http is available as 'http' module; fallback to socket.http if present.
local http = http or require("socket.http")
local ltn12 = require("ltn12")

-- ======= CONFIG (TODO tune to your ROM) =======
local MAILBOX_ADDR = 0x03005C00   -- EWRAM base (32KB window). Adjust if this collides.
-- Layout (bytes):
--   [0]: flag (0=idle, 1=request ready from ROM, 2=response ready from Lua)
--   [1]: prompt_id index (u8)          -- we map to strings here
--   [2]: attempt (u8)
--   [3]: answer_len (u8)
--   [4..67]: answer text (C-like, <=64 bytes)
--   [68..127]: response text buffer to write back (<=60 bytes for now)
local ANSWER_MAX = 64
local RESP_MAX = 60

-- Map prompt indices to ids (keep in sync with server/prompts.json)
local PROMPT_IDS = {
  [1] = "ARR_001",
}

local API_URL = "http://127.0.0.1:8000/ai"

-- memory helpers (BizHawk)
local function rb(addr) return memory.read_u8(addr, "EWRAM") end
local function wb(addr, val) memory.write_u8(addr, val, "EWRAM") end
local function rbytes(addr, n)
  local t = {}
  for i=0,n-1 do t[#t+1] = string.char(rb(addr+i)) end
  return table.concat(t)
end
local function wbytes(addr, s)
  for i=1,#s do wb(addr + (i-1), s:byte(i)) end
end
local function zstrip(s) return s:gsub("\0+$","") end

local function post_json(url, body_tbl)
  local body = json and json.stringify and json.stringify(body_tbl) or
               (function()
                  local ok, dk = pcall(require, "dkjson")
                  return ok and dk.encode(body_tbl) or error("No JSON encoder available")
                end)()
  local resp = {}
  local _, code = http.request{
    url = url,
    method = "POST",
    headers = {
      ["Content-Type"] = "application/json",
      ["Content-Length"] = tostring(#body)
    },
    source = ltn12.source.string(body),
    sink = ltn12.sink.table(resp)
  }
  return tonumber(code or 0), table.concat(resp)
end

while true do
  local flag = rb(MAILBOX_ADDR + 0)
  if flag == 1 then
    local pidx     = rb(MAILBOX_ADDR + 1)
    local attempt  = rb(MAILBOX_ADDR + 2)
    local ans_len  = math.min(rb(MAILBOX_ADDR + 3), ANSWER_MAX)
    local ans_raw  = rbytes(MAILBOX_ADDR + 4, ans_len)
    local answer   = zstrip(ans_raw)
    local pid      = PROMPT_IDS[pidx] or "ARR_001"

    -- Call server
    local code, body = post_json(API_URL, { prompt_id = pid, attempt = attempt, answer = answer })
    local reply = "Server?"
    if code == 200 and body then
      -- naive parse (expecting tiny JSON; we can improve)
      local text = body:match('"text"%s*:%s*"([^"]+)"') or "OK"
      reply = text
    else
      reply = "API error " .. tostring(code)
    end

    -- Truncate and write reply into response buffer
    if #reply > RESP_MAX then reply = reply:sub(1, RESP_MAX) end
    wbytes(MAILBOX_ADDR + 68, reply)
    wb(MAILBOX_ADDR + 0, 2) -- response ready
  end

  emu.frameadvance()
end
