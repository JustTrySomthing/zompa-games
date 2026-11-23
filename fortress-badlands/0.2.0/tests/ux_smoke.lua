package.path='./?.lua;'..package.path
local saved={};local texts={};local now=0
love={graphics={},timer={getTime=function()return now end},math={random=function(a,b)if a and b then return math.random(a,b) elseif a then return math.random(a) else return math.random() end end},filesystem={createDirectory=function()return true end,getInfo=function(k)return saved[k] and {type='file'} end,write=function(k,v)saved[k]=v;return true end,read=function(k)return saved[k] end,remove=function(k)saved[k]=nil;return true end}}
local g=love.graphics
for _,name in ipairs({'setColor','setFont','polygon','setLineWidth','circle','rectangle','line'}) do g[name]=function(...) end end
g.printf=function(t)texts[#texts+1]=tostring(t) end
g.newFont=function(size)return {size=size} end
local width,height=390,700
g.getDimensions=function()return width,height end
package.preload.zompa=function()return {mode=function()return 'solo',false end,saveSession=function(v)saved.session=v;return true end,loadSession=function()return saved.session end,clearSession=function()saved.session=nil;return true end,audio=function()return {update=function()end}end}end
local rules=require('rules')
dofile('main.lua');love.load()
local function paint()
  texts={};love.draw();return table.concat(texts,' ') end
local function tapCell(r,c)
  local radius=math.max(10,math.min((width-14)/(math.sqrt(3)*7.5),(height-133-49)/(2+1.5*12)))
  local tw=math.sqrt(3)*radius
  local cx=(width-tw*7.5)/2+tw/2+(c+(r%2)*.5)*tw
  local cy=49+radius+r*radius*1.5
  now=now+0.2;love.touchpressed(1,cx,cy)
end
assert(paint():find('TAP A SOLDIER TO VIEW ITS CARD',1,true))
tapCell(9,2)
local txt=paint()
for _,label in ipairs({'WARRIOR','MOVE','CAPTURE','HIT','DIE','D8','HP 19 / 19','GREEN = MOVE'}) do
  assert(txt:find(label,1,true),'missing character card label: '..label)
end
tapCell(8,2)
local after=paint()
assert(after:find('PLAYER 2',1,true),'moving consumes one turn')
assert(saved.session,'session saved')
tapCell(3,6)
assert(paint():find('ARCHER',1,true),'enemy card available')
for _,dims in ipairs({{280,480},{320,520},{420,850},{390,700}}) do
  width,height=dims[1],dims[2];love.resize(width,height)
  assert(paint():find('ARCHER',1,true),'card survives resize')
end
print('PASS: character cards, tap-to-move, enemy inspect, session, four portrait sizes')
