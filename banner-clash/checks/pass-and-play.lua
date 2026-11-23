local calls,slots={},{}
local noop=function()end
love={graphics=setmetatable({getDimensions=function()return 400,720 end,newImage=function()return {getDimensions=function()return 1254,1254 end,getWidth=function()return 1254 end,getHeight=function()return 1254 end}end,newQuad=function()return {}end,newFont=function()return {}end,printf=function(s,x,y) calls[s]={x+2,y+2} end},{__index=function()return noop end}),filesystem={createDirectory=function()return true end,write=function(k,v)slots[k]=v;return true end,getInfo=function(k)return slots[k]~=nil end,read=function(k)return slots[k]end}}
local function frame() calls={};love.draw() end
local function tap(s)frame();local v=assert(calls[s],s);love.mousepressed(v[1],v[2],1) end
dofile('main.lua');love.load()
for battle=1,3 do
 for turn=1,10 do tap("Show my hand");tap("Pass");tap("Confirm move") end
 for lock=1,2 do tap("Show my hand");tap("Hold");tap("Lock choice");if lock==1 then love.load();love.focus(false) end end
 frame();assert(calls["Both earn a banner"])
 if battle<3 then tap("Next battle") end
end
assert(calls["Match drawn"]);tap("Rematch");tap("Show my hand");tap("?");tap("Return")
print('UI handoff, confirmation, saved lock, draw, rematch and help paths passed')

tap("II");tap("Return")
frame();love.mousepressed(45,127,1);tap("?");frame();assert(calls["How to play"]);love.keypressed("acback");frame();assert(calls["Bridge"]);love.keypressed("escape");frame();assert(calls["Pass"])
local key="zompado-saves/banner-clash-v1"
slots[key]="s3:bad";love.load();love.focus(false);frame()
assert(calls["Match drawn"]);print("Malformed primary save restored previous valid result; modal and Android back passed")
