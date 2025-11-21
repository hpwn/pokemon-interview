-- Injects a test mailbox packet for BizHawk

local DOMAIN = "IWRAM"
local BASE   = 0x03000000
local MAILBOX_ADDR = 0x03005C00
local ANSWER_MAX   = 64

if not memory.usememorydomain then
  error("This script expects BizHawk (memory.usememorydomain).")
end

memory.usememorydomain(DOMAIN)
local mbox_off = MAILBOX_ADDR - BASE

local function wb(off, v)
  memory.write_u8(mbox_off + off, v, DOMAIN)
end

local function wbytes(off, s)
  for i = 1, #s do
    memory.write_u8(mbox_off + off + (i - 1), s:byte(i), DOMAIN)
  end
end

console.log(string.format("Injecting test packet at mailbox=%08X", MAILBOX_ADDR))

-- clear the mailbox region (~100 bytes)
for i = 0, 99 do
  wb(i, 0)
end

local pidx    = 1
local attempt = 1
local answer  = "test"
local ans_len = math.min(#answer, ANSWER_MAX)

wb(1, pidx)
wb(2, attempt)
wb(3, ans_len)
wbytes(4, answer:sub(1, ans_len))
wb(0, 1)

console.log(string.format("Test packet injected: pidx=%d attempt=%d answer='%s'", pidx, attempt, answer))
