-- Approved Fortress UI handoff regression: dynamic winner/bonus phases.
-- Runs without Android, with the same LÖVE APIs mocked as other tests.
package.path='./?.lua;'..package.path
local g={};local rendered={}
local fighters={}
love={graphics=g,timer={getTime=function()return 0 end},
 math={random=function(a,b) if a and b then return math.random(a,b) end
   if a then return math.random(a) end return math.random() end},
 filesystem={getInfo=function()return nil end,createDirectory=function()return true end,
 write=function()return true end,read=function()return nil end}}
for _,n in ipairs({'setColor','setFont','polygon','setLineWidth','circle',
 'rectangle','line','draw','setStencilTest'}) do g[n]=function()end end
g.printf=function(s) rendered[#rendered+1]=tostring(s) end
g.draw=function(image,x,y,angle,sx)
 if image.path:find('^fighters/') then fighters[image.path]={x=x,angle=angle,sx=sx} end
end
g.newFont=function(sz)return {size=sz} end
g.newImage=function(path)
 local w=path=='art/board.png' and 984 or 144
 local h=path=='art/board.png' and 1383 or 144
 return {path=path,getDimensions=function()return w,h end,getWidth=function()return w end,
  setFilter=function()end}
end
g.stencil=function(fn)fn()end
g.getDimensions=function()return 390,700 end
package.preload.zompa=function()return {
 mode=function()return 'solo',false end,
 audio=function()return {update=function()end}end,
 loadSession=function()return nil end,saveSession=function()return true end,
 clearSession=function()return true end
}end
local rules=require('rules')
dofile('main.lua')
love.load()
local function upval(name)
 for i=1,100 do
  local key,v=debug.getupvalue(love.draw,i)
  if key==name then return i,v end
  if not key then break end
 end
 error('missing draw upvalue '..name)
end
local index=upval('overlay')
local function setOverlay(o)
 debug.setupvalue(love.draw,index,o)
end
local function paint()
 rendered,fighters={},{}
 love.draw()
 return table.concat(rendered,' | ')
end
local function expect(output,needle)
 assert(output:find(needle,1,true),needle..' missing in '..output)
end
local event={type='attack',actor=1,attackerClass='assassin',defenderClass='soldier',
 attackerHpStart=10,defenderHpStart=10,defenderHpEnd=0,roll=12,shield=2,
 landed=true,damage=10,defeated=true,heal={roll=4,actual=4}}
local o={type='battle',elapsed=.35,event=event}
setOverlay(o)
local ready=paint()
expect(ready,'Ready for Combat')
expect(ready,'D12')
assert(not o.button)
o.elapsed=1.2
expect(paint(),'ATTACK ROLL')
assert(not o.button)
o.elapsed=2.45
paint()
local left,right='fighters/assassin-1.png','fighters/soldier-2.png'
local leftX,rightX=fighters[left].x,fighters[right].x
assert(fighters[left].sx>0 and fighters[right].sx<0)
o.elapsed=3.23
expect(paint(),'-10')
assert(fighters[left].x>leftX and fighters[left].angle>0)
assert(fighters[right].x>rightX)
o.elapsed=4.1
local result=paint()
expect(result,'VICTORY')
assert(not o.button and not o.bonusElapsed,'Victory should be visible before starting the bonus')
love.update(.5)
assert(o.bonusElapsed==0)
expect(paint(),'Bonus Roll')
love.update(2)
expect(paint(),'+4 Health')
expect(paint(),'CONTINUE')

local blocked={type='attack',actor=2,attackerClass='archer',defenderClass='wizard',
 attackerHpStart=14,defenderHpStart=18,roll=4,shield=4,landed=false}
setOverlay({type='battle',elapsed=4.15,event=blocked})
local repelled=paint()
expect(repelled,'ATTACK REPELLED')
expect(repelled,'Turn over')
expect(repelled,'CONTINUE')

local cpu={type='battle',elapsed=4.15,event=event}
event.actor=2
setOverlay(cpu)
love.update(1)
assert(cpu.bonusElapsed==0)
love.update(2)
expect(paint(),'CONTINUE')
print('PASS: impact animation, readable damage, repelled attack and player/CPU D12 victory bonus')

local full={type='attack',actor=1,attackerClass='archer',defenderClass='soldier',
 attackerHpStart=14,defenderHpStart=1,defenderHpEnd=0,roll=12,shield=2,
 landed=true,damage=1,defeated=true,fullHealth=true}
local fullView={type='battle',elapsed=5,event=full}
setOverlay(fullView)
local result=paint()
expect(result,'AMAZING')
expect(result,'Red Archer Has Full Health')
expect(result,'No Bonus Roll This Round')
expect(result,'CONTINUE')
assert(not fullView.bonusElapsed)
print('PASS: full-health result offers Continue immediately')
