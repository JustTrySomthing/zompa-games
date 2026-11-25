-- Approved Fortress UI handoff regression: dynamic winner/bonus phases.
-- Runs without Android, with the same LÖVE APIs mocked as other tests.
package.path='./?.lua;'..package.path
local clock=0
local g={};local rendered={}
local fighters={}
love={graphics=g,timer={getTime=function()return clock end},
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
local ui=require('tests.ui_geometry')
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
local function no(output,needle)
 assert(not output:find(needle,1,true),needle..' unexpectedly in '..output)
end
local function event(team,healAmount,roll)
 local leftIsRed=team==1
 local ah=team==1 and 20 or 18
 local winnerClass=team==1 and 'assassin' or 'soldier'
 return {
   type='attack',actor=team,attackerClass=winnerClass,
   defenderClass=team==1 and 'soldier' or 'assassin',
   attackerHpStart=ah,attackerHpEnd=ah,attackerHpAfter=ah+healAmount,
   defenderHpStart=5,defenderHpEnd=0,defenderHpAfter=0,
   rounds={{a=7,b=2,who='attacker',damage=6,attackerHp=ah,defenderHp=0}},
   heal={owner=team,roll=roll,actual=healAmount},
 }
end
-- Red and Blue combatants face each other, then lunge and recoil.
local redEvent=event(1,4,4)
local animation={type='battle',elapsed=1.3,event=redEvent}
setOverlay(animation)
paint()
local left,right='fighters/assassin-1.png','fighters/soldier-2.png'
local leftX,rightX=fighters[left].x,fighters[right].x
assert(fighters[left].sx>0 and fighters[right].sx<0,'the fighters must face each other')
animation.elapsed=2.08
paint()
assert(fighters[left].x>leftX and fighters[left].angle>0,'the Red attack should lunge and swing')
assert(fighters[right].x>rightX,'the Blue defender should recoil')
animation.elapsed=2.65
paint()
assert(fighters[left].x==leftX and fighters[right].x==rightX,'fighters should recover to their starting positions')
local o={type='battle',elapsed=3.7,event=redEvent}
setOverlay(o)
local initial=paint()
expect(initial,'RED ASSASSIN WINS!')
expect(initial,'VICTORY BONUS')
no(initial,'ROLL')
assert(not o.continueBox,'continue must wait for the bonus')
love.update(1.0)
local rolling=paint()
expect(rolling,'ROLLING')
no(rolling,'HEALTH BONUS +4')
love.update(1.25)
local result=paint()
expect(result,'HEALTH BONUS +4')
expect(result,'HEALTH 24/24')
expect(result,'CONTINUE')
no(result,'HEALTH BONUS +4 HP')
clock=2
love.touchpressed(1,ui.boxCenter(o.continueBox))
local _,after=upval('overlay')
assert(after==nil,'CONTINUE did not dismiss bonus result')
-- Blue also displays the automatically rolled reward.
setOverlay({type='battle',elapsed=6,event=event(2,3,3)})
local blueResult=paint()
expect(blueResult,'HEALTH BONUS +3')
expect(blueResult,'HEALTH 21/22')
-- If the unit is full, the actual die result still appears without +HP.
local full=event(1,0,7)
full.attackerHpStart=24;full.attackerHpEnd=24;full.attackerHpAfter=24
local f={type='battle',elapsed=20,event=full}
setOverlay(f)
local fullOut=paint()
expect(fullOut,'HEALTH FULL')
expect(fullOut,'HEALTH 24/24')
-- A tie never claims either kingdom hit before the roll resolves.
local tie=event(1,0,4)
tie.rounds[1]={a=4,b=4,who='tie',damage=0,attackerHp=14,defenderHp=5}
local tieOverlay={type='battle',event=tie,elapsed=1.6}
setOverlay(tieOverlay)
expect(paint(),'TIE!')
love.window={getSafeArea=function() return 0,0,240,298 end}
love.resize(240,320)
local small={type='battle',elapsed=3.7,event=redEvent}
setOverlay(small)
expect(paint(),'VICTORY BONUS')
love.update(2.1)
expect(paint(),'CONTINUE')
assert(small.continueBox.y+small.continueBox.h+3<=298-24,'battle continue extends outside the safe content area')
print('PASS: automatic red/blue bonus rolls, capped Health, single reward banner, tie, responsive Continue')
