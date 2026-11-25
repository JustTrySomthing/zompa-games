-- Regression: distinct red/blue portrait and token PNGs, live HUD typography.
package.path='./?.lua;'..package.path
local labels,drawn={},{}
local size={390,700}
local now=0
love={graphics={},timer={getTime=function()return now end},
 math={random=function(a,b) if a and b then return math.random(a,b) end
   if a then return math.random(a) end return math.random() end},
 filesystem={getInfo=function()return nil end,createDirectory=function()return true end,
  write=function()return true end,read=function()return nil end}}
local g=love.graphics
for _,k in ipairs({'setColor','setFont','polygon','setLineWidth','circle',
 'rectangle','line','setStencilTest'}) do g[k]=function()end end
g.printf=function(value)labels[#labels+1]=tostring(value) end
g.newFont=function(pt)return {size=pt}end
g.getDimensions=function()return size[1],size[2] end
g.stencil=function(fn)fn()end
local loaded={}
g.newImage=function(path)
 local f=assert(io.open(path,'rb'),'missing game art: '..path)
 local sig=f:read(8);f:close()
 assert(sig=='\137PNG\r\n\026\n','invalid PNG: '..path)
 loaded[path]=true
 local ww,hh=144,144
 if path:find('^portraits/') then ww,hh=240,240 end
 if path=='art/board.png' then ww,hh=984,1383 end
 return {path=path,getDimensions=function()return ww,hh end,
  getWidth=function()return ww end,setFilter=function()end}
end
g.draw=function(sprite)drawn[#drawn+1]=sprite.path end
package.preload.zompa=function()return {
 mode=function()return 'solo',false end,audio=function()return {update=function()end}end,
 saveSession=function()return true end,loadSession=function()return nil end,
 clearSession=function()return true end
}end
local rules=require('rules')
dofile('main.lua');love.load()
local function slot(fn,name)
 for i=1,100 do
  local k,v=debug.getupvalue(fn,i)
  if k==name then return i,v end
  if not k then break end
 end
 error('missing upvalue '..name)
end
local _,drawCard=slot(love.draw,'drawCard')
local inspIndex=slot(drawCard,'inspected')
local _,state=slot(love.draw,'state')
local function paint()
 labels,drawn={},{}
 love.draw()
 return table.concat(labels,' | '),table.concat(drawn,' | ')
end
local function contains(value,substr)
 assert(value:find(substr,1,true),substr..' missing in '..value)
end
for _,class in ipairs({'soldier','ogre','barbarian','assassin','wizard','archer'}) do
 for team=1,2 do
  local id
  for _,u in ipairs(state.units) do if u.class==class and u.owner==team then id=u.id;break end end
  assert(id)
  local u=state.units[id]
  debug.setupvalue(drawCard,inspIndex,id)
  local title,images=paint()
  local expected=(team==1 and 'RED ' or 'BLUE ')..class:upper()
  contains(title,expected)
  contains(title,('HEALTH %d / %d'):format(u.hp,rules.classes[class].hp))
  contains(title,('MOVE %s'):format(rules.classes[class].move or 'LINE'))
  contains(title,('HIT %d'):format(rules.classes[class].hit))
  contains(images,('portraits/%s-%d.png'):format(class,team))
  assert(loaded[('fighters/%s-%d.png'):format(class,team)],'missing battle cutout')
  assert(not title:find('P1',1,true) and not title:find('P2',1,true),
    'outdated player ID displayed')
  assert(not title:find('MARCH',1,true) and not title:find('TELEPORT',1,true),
    'card text should say MOVE')
 end
end
for _,kind in ipairs({'ogre','wizard','archer','fortress'}) do
 for team=1,2 do
  assert(loaded[('art/%s-%d.png'):format(kind,team)],'new token asset not loaded')
 end
end
-- A wounded piece must show current HP, not just maximum HP.
local u=state.units[1]
u.hp=u.hp-5
local max=rules.classes[u.class].hp
debug.setupvalue(drawCard,inspIndex,u.id)
local label=paint()
contains(label,('HEALTH %d / %d'):format(u.hp,max))
-- The Fortress is also live art, without player numbers.
local fortIndex=slot(drawCard,'inspectedFortOwner')
debug.setupvalue(drawCard,fortIndex,1)
debug.setupvalue(drawCard,inspIndex,'fort')
local ftitle,drawnPaths=paint()
contains(ftitle,'RED FORTRESS')
contains(ftitle,'HEALTH 50 / 50')
contains(drawnPaths,'art/fortress-1.png')
print('PASS: 12 matching profile portraits and board art, live colored names, current/max HP, MOVE/HIT, no P1/P2')
