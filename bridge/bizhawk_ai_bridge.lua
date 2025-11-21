-- BizHawk AI bridge that polls a mailbox in IWRAM and calls the FastAPI server

--------------------------------------
-- Config
--------------------------------------
local DOMAIN = "IWRAM"
local BASE   = 0x03000000
local MAILBOX_ADDR = 0x03005C00
local ANSWER_MAX   = 64
local RESP_MAX     = 60
local API_URL      = "http://localhost:8000/ai"

local PROMPT_IDS = {
  [1] = "ARR_001",
}

--------------------------------------
-- Memory helpers (BizHawk)
--------------------------------------
if not memory.usememorydomain then
  error("This script expects BizHawk (memory.usememorydomain).")
end

memory.usememorydomain(DOMAIN)
local mbox_off = MAILBOX_ADDR - BASE

local function rb(off)
  return memory.read_u8(mbox_off + off, DOMAIN)
end

local function wb(off, v)
  memory.write_u8(mbox_off + off, v, DOMAIN)
end

local function rbytes(off, n)
  local t = {}
  for i = 0, n - 1 do
    t[#t + 1] = string.char(rb(off + i))
  end
  return table.concat(t)
end

local function wbytes(off, s)
  for i = 1, #s do
    memory.write_u8(mbox_off + off + (i - 1), s:byte(i), DOMAIN)
  end
end

local function zstrip(s)
  return (s or ""):gsub("\0+$", "")
end

--------------------------------------
-- HTTP helpers
--------------------------------------
local have_comm = type(comm) == "table" and comm.httpPost

local socket_http, ltn12
local ok_http, mod_http = pcall(require, "socket.http")
local ok_ltn12, mod_ltn12 = pcall(require, "ltn12")
if ok_http and ok_ltn12 then
  socket_http = mod_http
  ltn12 = mod_ltn12
end

local function to_json(tbl)
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
      local is_array = (next(v) == 1)
      if is_array then
        for i = 1, #v do parts[#parts + 1] = enc(v[i]) end
        return "[" .. table.concat(parts, ",") .. "]"
      else
        for k, val in pairs(v) do
          parts[#parts + 1] = '"' .. tostring(k) .. '":' .. enc(val)
        end
        return "{" .. table.concat(parts, ",") .. "}"
      end
    else
      return "null"
    end
  end
  return enc(tbl)
end

local function post_via_comm(url, body)
  if not have_comm then return nil, nil, "No comm.httpPost" end
  local ok, resp = pcall(function()
    return comm.httpPost(url, body, "application/json")
  end)
  if not ok then return nil, nil, tostring(resp) end
  if type(resp) == "table" then
    local code = tonumber(resp.StatusCode or resp.status or resp.statusCode or resp.code)
    local text = resp.Text or resp.text or resp.Body or resp.body
    return code or 0, text or "", nil
  end
  return 200, tostring(resp), nil
end

local function post_via_luasocket(url, body)
  if not socket_http or not ltn12 then return nil, nil, "No socket.http" end
  local resp_t = {}
  local code, code_str = socket_http.request{
    url = url,
    method = "POST",
    headers = {
      ["Content-Type"]   = "application/json",
      ["Content-Length"] = tostring(#body),
    },
    source = ltn12.source.string(body),
    sink   = ltn12.sink.table(resp_t),
  }
  if not code then return nil, nil, tostring(code_str) end
  return tonumber(code) or 0, table.concat(resp_t), nil
end

local function post_json(url, tbl)
  local body = to_json(tbl)

  local code, text, err = post_via_comm(url, body)
  if code then return code, text, err end

  code, text, err = post_via_luasocket(url, body)
  if code then return code, text, err end

  return -1, nil, "No HTTP client available"
end

--------------------------------------
-- Startup
--------------------------------------
console.clear()
console.log(string.format(
  "AI bridge started. Domain=%s base=%08X mailbox=%08X (offset %d) RESP_MAX=%d",
  DOMAIN, BASE, MAILBOX_ADDR, mbox_off, RESP_MAX))

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
  local flag = rb(0)
  if flag == 1 then
    local pidx    = rb(1)
    local attempt = rb(2)
    local ans_len = math.min(rb(3), ANSWER_MAX)
    local answer  = zstrip(rbytes(4, ans_len))
    local pid     = PROMPT_IDS[pidx] or "ARR_001"

    local payload = { prompt_id = pid, attempt = attempt, answer = answer }
    local code, body, err = post_json(API_URL, payload)

    local reply
    if code == 200 and body then
      reply = body:match('"text"%s*:%s*"([^"]+)"') or body
    else
      if err then
        reply = string.format("API error %s (%s)", tostring(code), err)
      elseif body and #body > 0 then
        reply = string.format("API error %s (%s)", tostring(code), body:gsub("[%c]", " "):sub(1, 120))
      else
        reply = string.format("API error %s", tostring(code))
      end
    end

    if #reply > RESP_MAX then
      reply = reply:sub(1, RESP_MAX)
    end

    wbytes(68, reply)
    wb(0, 2)

    console.log(string.format(
      "Processed pidx=%d pid=%s attempt=%d -> code=%s reply='%s'",
      pidx, pid, attempt, tostring(code), reply))
  end

  heartbeat()
  emu.frameadvance()
end
