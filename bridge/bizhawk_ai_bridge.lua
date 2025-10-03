-- BizHawk-safe Lua: .NET WebClient + IWRAM offsets + WinForms input
-- Inputs supported: mcq/tf via dialog, short/code via TextBox.
-- Dev hotkey K injects a test request.

-- ===== CONFIG =====
local MAILBOX_ADDR = 0x03005C00  -- IWRAM base region for mailbox
local DOMAIN       = "IWRAM"
local DOMAIN_BASE  = 0x03000000
local ANSWER_MAX   = 200   -- allow longer text answers
local RESP_MAX     = 120
local API_URL      = "http://127.0.0.1:8000/ai"

-- ===== Domain helpers =====
local function dom_size() return memory.getmemorydomainsize(DOMAIN) end
local function to_off(addr) return addr - DOMAIN_BASE end
local function in_range(off) return off >= 0 and off < dom_size() end
local function rb_addr(addr) local off=to_off(addr); if not in_range(off) then return 0 end; return memory.read_u8(off, DOMAIN) end
local function wb_addr(addr, v) local off=to_off(addr); if not in_range(off) then return end; memory.write_u8(off, v, DOMAIN) end
local function rbytes(addr,n) local t={}; for i=0,n-1 do t[#t+1]=string.char(rb_addr(addr+i)) end; return table.concat(t) end
local function wbytes(addr,s) for i=1,#s do wb_addr(addr+(i-1), s:byte(i)) end end
local function zstrip(s) return (s or ""):gsub("\0+$","") end
local function clear(addr,n) for i=0,n-1 do wb_addr(addr+i,0) end end

-- ===== .NET interop =====
if not luanet then luanet = require("luanet") end
local WebClient = luanet.import_type('System.Net.WebClient')
local Encoding  = luanet.import_type('System.Text.Encoding')
local Form      = luanet.import_type('System.Windows.Forms.Form')
local Label     = luanet.import_type('System.Windows.Forms.Label')
local Button    = luanet.import_type('System.Windows.Forms.Button')
local TextBox   = luanet.import_type('System.Windows.Forms.TextBox')
local CheckedListBox = luanet.import_type('System.Windows.Forms.CheckedListBox')
local DialogResult  = luanet.import_type('System.Windows.Forms.DialogResult')
local DockStyle  = luanet.import_type('System.Windows.Forms.DockStyle')

local function http_post_json(url, body)
  local wc = WebClient()
  wc.Headers["Content-Type"] = "application/json"
  local bytes = wc:UploadData(url, "POST", Encoding.UTF8:GetBytes(body))
  return 200, Encoding.UTF8:GetString(bytes)
end

local function json_escape(s) s=s or ""; s=s:gsub('\\','\\\\'):gsub('"','\\"'):gsub('\n','\\n'):gsub('\r','\\r'); return s end
local function make_body(tbl)
  local parts = {}
  local function add(k,v)
    if v==nil then return end
    local val = (type(v)=="string") and ('"'..json_escape(v)..'"') or tostring(v)
    parts[#parts+1] = '"'..k..'":'..val
  end
  add("prompt_id", tbl.prompt_id)
  add("attempt", tbl.attempt or 1)
  add("answer_text", tbl.answer_text)
  add("answer_idx", tbl.answer_idx)
  if tbl.answer_bool ~= nil then add("answer_bool", tbl.answer_bool and "true" or "false") end
  return "{"..table.concat(parts, ",").."}"
end
local function parse_json_value(body, key)
  return (body or ""):match('"'..key..'"%s*:%s*"([^"]*)"')
end
local function parse_choices(body)
  local arr = {}
  local section = (body or ""):match('"choices"%s*:%s*%[(.-)%]')
  if not section then return nil end
  for s in section:gmatch('"(.-)"') do arr[#arr+1] = s end
  return arr
end

-- ===== UI Widgets =====
local function show_textbox(title, prompt, initial)
  local f = Form()
  f.Text = title
  f.Width = 600; f.Height = 240
  local lbl = Label(); lbl.Text = prompt; lbl.Dock = DockStyle.Top; lbl.Height = 60
  local tb = TextBox(); tb.Multiline = true; tb.Dock = DockStyle.Fill; tb.Text = initial or ""
  local ok = Button(); ok.Text = "OK"; ok.Dock = DockStyle.Bottom
  local cancel = Button(); cancel.Text = "Cancel"; cancel.Dock = DockStyle.Bottom
  local result = nil
  ok.Click:Add(function() result = tb.Text; f:Close() end)
  cancel.Click:Add(function() result = nil; f:Close() end)
  f.Controls:Add(tb); f.Controls:Add(ok); f.Controls:Add(cancel); f.Controls:Add(lbl)
  f:ShowDialog()
  return result
end

local function show_mcq(title, prompt, choices, allow_tf_bool)
  local f = Form(); f.Text = title; f.Width=500; f.Height=360
  local lbl = Label(); lbl.Text = prompt; lbl.Dock=DockStyle.Top; lbl.Height=60
  local clb = CheckedListBox(); clb.Dock = DockStyle.Fill
  for i,c in ipairs(choices or {"True","False"}) do clb.Items:Add(c) end
  clb.CheckOnClick = true
  local ok = Button(); ok.Text="OK"; ok.Dock=DockStyle.Bottom
  local cancel = Button(); cancel.Text="Cancel"; cancel.Dock=DockStyle.Bottom
  local idx = nil
  ok.Click:Add(function()
    for i=0, clb.Items.Count-1 do
      if clb:GetItemChecked(i) then idx = i; break end
    end
    f:Close()
  end)
  cancel.Click:Add(function() idx = nil; f:Close() end)
  f.Controls:Add(clb); f.Controls:Add(ok); f.Controls:Add(cancel); f.Controls:Add(lbl)
  f:ShowDialog()
  if allow_tf_bool and choices == nil then
    if idx == 0 then return nil, true
    elseif idx == 1 then return nil, false
    end
  end
  return idx, nil
end

print(string.format("AI bridge (expansion) started. Domain=%s base=%08X size=%d",
  DOMAIN, DOMAIN_BASE, dom_size()))

-- Dev hotkey
local function inject_test_request()
  clear(MAILBOX_ADDR, 256)
  wb_addr(MAILBOX_ADDR + 1, 1)   -- prompt idx (server will map by id)
  wb_addr(MAILBOX_ADDR + 2, 1)   -- attempt
  wb_addr(MAILBOX_ADDR + 3, 0)   -- answer_len
  wb_addr(MAILBOX_ADDR + 0, 1)   -- flag=1
  print("Injected test request.")
end

while true do
  local keys = input and input.get and input.get() or {}
  if keys["K"] then inject_test_request() end

  local flag = rb_addr(MAILBOX_ADDR + 0)
  if flag == 1 then
    local pidx    = rb_addr(MAILBOX_ADDR + 1)
    local attempt = rb_addr(MAILBOX_ADDR + 2)
    -- First post to fetch question (+ choices)
    local req0 = make_body({ prompt_id = "MCQ_001", attempt = attempt }) -- default if ROM didn't set id
    local ok0, code0, body0 = pcall(function() local wc=WebClient(); wc.Headers["Content-Type"]="application/json"; local b=wc:UploadData(API_URL,"POST",Encoding.UTF8:GetBytes(req0)); return 200, Encoding.UTF8:GetString(b) end)
    local qtext = parse_json_value(ok0 and body0 or "", "text") or "Question"
    local choices = parse_choices(ok0 and body0 or "")

    -- Decide input modality: if choices -> mcq/tf; else -> textbox
    local answer_idx, answer_bool, answer_text = nil, nil, nil
    if choices and #choices > 0 then
      answer_idx, answer_bool = show_mcq("Trainer Question", qtext, choices, false)
    else
      -- try TF if no explicit choices but question looks T/F
      if qtext:lower():match("^true/false") or qtext:lower():match("true or false") then
        _, answer_bool = show_mcq("True / False", qtext, {"True","False"}, true)
      else
        answer_text = show_textbox("Short/Code Answer", qtext, "")
      end
    end

    -- Second post with answer
    local req1 = make_body({
      prompt_id = "MCQ_001",  -- keep consistent for MVP; ROM can set later
      attempt = attempt + 1,
      answer_text = answer_text,
      answer_idx = answer_idx,
      answer_bool = answer_bool
    })
    local ok1, code1, body1 = pcall(function() local wc=WebClient(); wc.Headers["Content-Type"]="application/json"; local b=wc:UploadData(API_URL,"POST",Encoding.UTF8:GetBytes(req1)); return 200, Encoding.UTF8:GetString(b) end)
    local reply = parse_json_value(ok1 and body1 or "", "text") or "OK"

    if #reply > RESP_MAX then reply = reply:sub(1, RESP_MAX) end
    clear(MAILBOX_ADDR + 68, 140)
    wbytes(MAILBOX_ADDR + 68, reply)
    wb_addr(MAILBOX_ADDR + 0, 2) -- response ready
    print("AI reply written.")
  end

  emu.frameadvance()
end
