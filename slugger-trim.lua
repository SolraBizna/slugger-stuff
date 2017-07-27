#!/usr/bin/env lua

local function printf(format, ...) return print(format:format(...)) end
if #arg ~= 3 and (#arg ~= 4 or arg[4] ~= "-v") then
   printf("Usage: %s base grace resolution\nExample: %s /meat 100 10000\n  (leave one snapshot per hour, sparing snapshots made within the current\n   minute)\nif grace and resolution are both 0, deletes the oldest snapshot that exists for any machine that still has at least one snapshot\nAdd -v to the end of the command line to print statistics on deleted and renamed snapshots", arg[0], arg[0])
   os.exit(1)
end

local verbose = arg[4] == "-v"

local old_execute = os.execute
function os.execute(...)
   assert(old_execute(...))
end

local lfs = require "lfs"

local base = assert(arg[1], "Bad base?")
local grace = assert(tonumber(arg[2]), "Bad grace?")
local resolution = assert(tonumber(arg[3]), "Bad resolution?")

assert(not base:match("[^-A-Za-z0-9_/]"), "Weird base? (Check may need expanding)")
assert(grace >= 0 and grace % 1 == 0, "Weird grace?")
assert(resolution >= 0 and resolution % 1 == 0, "Weird resolution?")
if grace == 0 then assert(resolution == 0, "if grace is 0, so must resolution be") end

local function parse_when(x)
   local lr = x:match("^@?([0-9][0-9][0-9][0-9]%.?[0-9]?[0-9]?%.?[0-9]?[0-9]?%-?[0-9]?[0-9]?[0-9]?[0-9]?%.?[0-9]?[0-9]?)$")
   if lr then
      lr = lr:gsub("[-.]","")
      return assert(tonumber(lr .. ("0"):rep(14-#lr)))
   else
      return nil
   end
end

local now = assert(tonumber(os.date("%Y%m%d%H%M%S", os.time())))
local grace_time = now - now % grace

local snaps = {}
for machine in lfs.dir(base) do
   if machine:sub(1,1) == "." then goto continue end
   for dir in lfs.dir(base.."/"..machine) do
      if dir:sub(1,1) ~= "@" then goto continue2 end
      local when = parse_when(dir)
      if when then
         snaps[#snaps+1] = {machine=machine,when=when,time=dir:sub(2,-1)}
      end
      ::continue2::
   end
   ::continue::
end

table.sort(snaps, function(a,b) return a.when < b.when end)

local latests = {}
local function get_latest(machine)
   if latests[machine] ~= nil then
      return latests[machine] or nil
   else
      local p = io.popen("/bin/readlink "..base.."/"..machine.."/latest 2>/dev/null", "r")
      local l = p:read("*l")
      p:close()
      if l and l:sub(1,1) == "@" then
         l = parse_when(l)
         latests[machine] = l
         return l
      else
         latests[machine] = false
         return nil
      end
   end
end

if grace > 0 then
   -- calculate which snapshots deserve to be kept, by putting each one into
   -- a resolution-sized bucket and keeping only the latest one in each bucket
   local whens = {}
   for n=1,#snaps do
      local snap = snaps[n]
      if snap.when >= grace_time then
	 snap.keep = "SAFE"
      else
	 local i = math.floor(snap.when / resolution)
	 local when = whens[snap.machine]
	 if not when then
	    when = {}
	    whens[snap.machine] = when
	 end
	 local why = when[i]
	 if not why or why.when < snap.when then
	    when[i] = snap
	 end
      end
   end
   for name,when in pairs(whens) do
      for why,snap in pairs(when) do
	 snap.keep = "KEEP"
      end
   end
   for n=1,#snaps do
      local snap = snaps[n]
      -- print(snaps[n].machine.."@"..snaps[n].time..": "..(snaps[n].keep or "KILL"),snaps[n].when)
      if not snap.keep then
         if verbose then
            printf("Discard %s/@%s", snap.machine, snap.time)
         end
	 os.execute("/bin/rm -rf --one-file-system "..base.."/"..snap.machine.."/@"..snap.time)
      elseif snap.keep == "KEEP" then
         local latest = get_latest(snap.machine)
         if latest ~= nil and snap.when < latest then
            local trimtime = snap.when - snap.when % resolution
            local trimdig = 1
            while trimdig * 10 <= resolution do trimdig = trimdig * 10 end
            local name = tostring(math.floor(snap.when/trimdig))
            if #name > 12 then name = name:sub(1,12).."."..name:sub(13,-1) end
            if #name > 8 then name = name:sub(1,8).."-"..name:sub(9,-1) end
            if #name > 6 then name = name:sub(1,6).."."..name:sub(7,-1) end
            if #name > 4 then name = name:sub(1,4).."."..name:sub(5,-1) end
            if name ~= snap.time and #name < #snap.time then
               if verbose then
                  printf("Rename %s/@%s -> @%s", snap.machine, snap.time,
                         name)
               end
               os.execute("/bin/mv "..base.."/"..snap.machine.."/@"..snap.time.." "..base.."/"..snap.machine.."/@"..name)
            end
         end
      end
   end
else
   -- grace 0 and resolution 0 means delete the oldest snapshot (as long as
   -- that machine still has at least one snapshot)
   local snapcounts = {}
   for n=1,#snaps do
      local snap = snaps[n]
      snapcounts[snap.machine] = (snapcounts[snap.machine] or 0) + 1
   end
   for n=1,#snaps do
      local snap = snaps[n]
      if snapcounts[snap.machine] > 1 then
         if verbose then
            printf("Discard %s/@%s", snap.machine, snap.time)
         end
	 os.execute("/bin/rm -rf --one-file-system "..base.."/"..snap.machine.."/@"..snap.time)
	 return
      end
   end
   print("NOT ENOUGH SNAPSHOTS FOR US TO DELETE ONE")
   os.exit(1)
end
