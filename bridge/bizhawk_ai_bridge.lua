-- BizHawk-safe AI bridge with HTTP fallbacks (http -> LuaSocket -> curl.exe)
-- Shows ticks so you know it's alive; safe in IWRAM on GBA.

--------------------------------------
-- Config
--------------------------------------
local MAILBOX_ADDR = 0x03005C00   -- absolute GBA addr we picked
local ANSWER_MAX   = 64
local RESP_MAX     = 60
local API_URL      = "http://192.168.0.160:8000/ai"

local PROMPT_IDS = {
  [1] = "ARR_001",
}

--------------------------------------
-- Memory helpers (BizHawk)
--------------------------------------
local function set_domain_iwram()
  if not memory.usememorydomain then
    error("This script expects BizHawk (memory.usememorydomain).")
  end
  memory.usememorydomain("IWRAM")
end

local function rb_off(base, off) return memory.read_u8(base + off) end
local function wb_off(base, off, v) memory.write_u8(base + off, v) end

local function rbytes_off(base, off, n)
  local t = {}
  for i = 0, n - 1 do
    t[#t + 1] = string.char(rb_off(base, off + i))
  end
  return table.concat(t)
end

local function wbytes_off(base, off, s)
  for i = 1, #s do
    memory.write_u8(base + off + (i - 1), s:byte(i))
  end
end

local function zstrip(s) return (s or ""):gsub("\0+$", "") end

--------------------------------------
-- HTTP helpers (3 fallbacks)
--------------------------------------
local have_bizhawk_http = (type(http) == "table" and (http.get or http.post))

local have_luasocket = false
local socket_http, ltn12
do
  local ok1, mod1 = pcall(require, "socket.http")
  local ok2, mod2 = pcall(require, "ltn12")
  if ok1 and ok2 then
    socket_http = mod1
    ltn12 = mod2
    have_luasocket = true
  end
end

local function post_via_http(url, body)
  -- BizHawk's 'http' module shape varies; try the common post signature.
  if not have_bizhawk_http then return nil, "no http module" end
  local ok, resp = pcall(function()
    if http.post then
      return http.post(url, body, { ["Content-Type"] = "application/json" })
    elseif http.request then
      return http.request({ url = url, method = "POST", data = body, headers = { ["Content-Type"] = "application/json" } })
    end
  end)
  if not ok then return nil, tostring(resp) end
  -- Some versions return {statusCode=..., text=...}; others just text
  if type(resp) == "table" then
    return tonumber(resp.statusCode or resp.status or 200) or 200, tostring(resp.text or resp.body or "")
  else
    return 200, tostring(resp)
  end
end

local function post_via_luasocket(url, body)
  if not have_luasocket then return nil, "no luasocket" end
  local resp_t = {}
  local code, code_str = socket_http.request{
    url = url,
    method = "POST",
    headers = { ["Content-Type"] = "application/json",
                ["Content-Length"] = tostring(#body) },
    source = ltn12.source.string(body),
    sink = ltn12.sink.table(resp_t)
  }
  if not code then return nil, tostring(code_str) end
  return tonumber(code) or 0, table.concat(resp_t)
end

local function esc(s)
  -- escape for cmd.exe
  s = s:gsub('"', '\\"')
  return '"' .. s .. '"'
end

local function post_via_curl(url, body)
  -- Windows 10+ has curl.exe in PATH
  local cmd = 'curl -s -S -o - -w "\\nHTTPSTATUS:%{http_code}" -X POST -H "Content-Type: application/json" --data ' ..
              esc(body) .. " " .. esc(url)
  local pipe = io.popen(cmd, "r")
  if not pipe then return nil, "popen failed" end
  local out = pipe:read("*a") or ""
  pipe:close()
  local body_part, status = out:match("^(.*)HTTPSTATUS:(%d+)%s*$")
  if not body_part then return nil, "curl parse fail" end
  return tonumber(status) or 0, body_part
end

local function to_json(tbl)
  -- tiny JSON encoder for our simple payload
  local function enc(v)
    local t = type(v)
    if t == "string" then
      return '"' .. v:gsub('\\','\\\\'):gsub('"','\\"'):gsub('\n','\\n') .. '"'
    elseif t == "number" then
      return tostring(v)
    elseif t == "boolean" then
      return v and "true" or "false"
    elseif t == "table" then
      local parts = {}
      local is_array = (next(v) == 1) -- cheap guess
      if is_array then
        for i=1,#v do parts[#parts+1] = enc(v[i]) end
        return "[" .. table.concat(parts, ",") .. "]"
      else
        for k,val in pairs(v) do
          parts[#parts+1] = '"' .. tostring(k) .. '":' .. enc(val)
        end
        return "{" .. table.concat(parts, ",") .. "}"
      end
    else
      return "null"
    end
  end
  return enc(tbl)
end

local function post_json(url, tbl)
  local body = to_json(tbl)
  -- try BizHawk http
  if have_bizhawk_http then
    local code, text = post_via_http(url, body)
    if code then return code, text end
  end
  -- try LuaSocket
  if have_luasocket then
    local code, text = post_via_luasocket(url, body)
    if code then return code, text end
  end
  -- fallback: curl.exe
  local code, text = post_via_curl(url, body)
  if code then return code, text end
  return -1, "No HTTP client available"
end

--------------------------------------
-- Startup
--------------------------------------
set_domain_iwram()
local DOMAIN = memory.getcurrentmemorydomain()
local base
if DOMAIN == "IWRAM" then base = 0x03000000
elseif DOMAIN == "EWRAM" then base = 0x02000000
else base = 0 end

local mbox_off = MAILBOX_ADDR - base
console.clear()
console.log(string.format(
  "AI bridge started. Domain=%s base=%08X mailbox=%08X (offset %d) RESP_MAX=%d",
  DOMAIN, base, MAILBOX_ADDR, mbox_off, RESP_MAX))

-- simple tick so we know it’s alive
local tick = 0
local function heartbeat()
  tick = tick + 1
  if tick % 120 == 0 then
    console.log("bridge tick " .. tick)
  end
end

--------------------------------------
-- Main loop
--------------------------------------
while true do
  -- read flag
  local flag = rb_off(mbox_off, 0)
  if flag == 1 then
    local pidx    = rb_off(mbox_off, 1)
    local attempt = rb_off(mbox_off, 2)
    local ans_len = math.min(rb_off(mbox_off, 3), ANSWER_MAX)
    local answer  = zstrip(rbytes_off(mbox_off, 4, ans_len))
    local pid     = PROMPT_IDS[pidx] or "ARR_001"

    local payload = { prompt_id = pid, attempt = attempt, answer = answer }
    local code, body = post_json(API_URL, payload)
    local reply = "Server?"
    if code == 200 and body then
      local txt = body:match('"text"%s*:%s*"([^"]+)"')
      reply = txt or "OK"
    else
      reply = "API error " .. tostring(code)
      if body and #body > 0 then reply = reply .. " (" .. body:gsub("[%c]"," "):sub(1,120) .. ")" end
    end

    if #reply > RESP_MAX then reply = reply:sub(1, RESP_MAX) end
    wbytes_off(mbox_off, 68, reply)
    wb_off(mbox_off, 0, 2) -- response ready
    console.log(string.format(
      "Processed pidx=%d pid=%s attempt=%d -> code=%s reply='%s'",
      pidx, pid, attempt, tostring(code), reply))
  end

  heartbeat()
  emu.frameadvance()
end
