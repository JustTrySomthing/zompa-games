-- Approved Fortress UI handoff regression: dynamic winner/bonus phases.
-- Runs without Android, with the same LÖVE APIs mocked as other tests.
package.path='./?.lua;'..package.path
local clock=0
local g={};local rendered={}
love={graphics=g,timer={getTime=function()return clock end},
 math={random=function(a,b) if a and b then return math.random(a,b) end
   if a then return math.random(a) end return math.random() end},
 filesystem={getInfo=function()return nil end,createDirectory=function()return true end,
 write=function()return true end,read=function()return nil end}}
for _,n in ipairs({'setColor','setFont','polygon','setLineWidth','circle',
 'rectangle','line','draw','setStencilTest'}) do g[n]=function()end end
g.printf=function(s) rendered[#rendered+1]=tostring(s) end
g.newFont=function(sz)return {size=sz} end
g.newImage=function(path)
 local w=path=='art/board.png' and 984 or 144
 local h=path=='art/board.png' and 1383 or 144
 return {getDimensions=function()return w,h end,getWidth=function()return w end,
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
 rendered={}
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
 local ah=team==1 and 10 or 18
 local max=team==1 and 14 or 22
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
-- Red human victory: both combat dice are visible at the ROLL prompt.
local redEvent=event(1,4,4)
local o={type='battle',elapsed=20,event=redEvent,
 autoHeal=false,healRevealed=false}
setOverlay(o)
local initial=paint()
expect(initial,'RED ASSASSIN WINS!')
expect(initial,'RED ROLLS FOR VICTORY BONUS')
expect(initial,'ROLL')
no(initial,'HEALTH BONUS +')
-- Tap it exactly once, release old pair of combat dice, begin bonus die.
local buttonX,buttonY=ui.boxCenter(o.healRollBox)
clock=1
love.touchpressed(1,buttonX,buttonY)
assert(o.healRevealed and o.healRolling==0)
clock=1.2
love.touchpressed(1,buttonX,buttonY)
assert(o.healRolling==0,'repeat tap restarted the already-committed die')
local rolling=paint()
no(rolling,'RED ROLLS FOR VICTORY BONUS')
no(rolling,'HEALTH BONUS +4')
love.update(1.25)
local result=paint()
expect(result,'HEALTH BONUS +4')
expect(result,'HP 14/14')
expect(result,'CONTINUE')
no(result,'HEALTH BONUS +4 HP')
clock=2
love.touchpressed(1,ui.boxCenter(o.continueBox))
local _,after=upval('overlay')
assert(after==nil,'CONTINUE did not dismiss bonus result')
-- Blue CPU should start its roll automatically when a blue soldier wins.
local blueEvent=event(2,3,3)
local cpu={type='battle',elapsed=20,event=blueEvent,
 autoHeal=true,healRevealed=false}
setOverlay(cpu)
local waiting=paint()
expect(waiting,'BLUE SOLDIER WINS!')
expect(waiting,'BLUE ROLLS FOR VICTORY BONUS')
expect(waiting,'WAITING FOR ROLL')
clock=3
love.touchpressed(1,buttonX,buttonY)
assert(cpu.healRevealed==false,'losing player triggered CPU bonus')
love.update(.10)
assert(cpu.healRevealed==true,'blue CPU reward should roll automatically')
love.update(1.25)
local blueResult=paint()
expect(blueResult,'HEALTH BONUS +3')
expect(blueResult,'HP 21/22')
-- If the unit is full, the actual die result still appears without +HP.
local full=event(1,0,7)
full.attackerHpStart=14;full.attackerHpEnd=14;full.attackerHpAfter=14
local f={type='battle',elapsed=20,event=full,
 autoHeal=false,healRevealed=true,healRolling=2}
setOverlay(f)
local fullOut=paint()
expect(fullOut,'HEALTH FULL')
expect(fullOut,'HP 14/14')
-- A tie never claims either kingdom hit before the roll resolves.
local tie=event(1,0,4)
tie.rounds[1]={a=4,b=4,who='tie',damage=0,attackerHp=14,defenderHp=5}
local tieOverlay={type='battle',event=tie,elapsed=1.6,
 autoHeal=false,healRevealed=false}
setOverlay(tieOverlay)
expect(paint(),'TIE!')
love.window={getSafeArea=function() return 0,0,240,298 end}
love.resize(240,320)
local small={type='battle',elapsed=20,event=redEvent,autoHeal=false,healRevealed=false}
setOverlay(small)
expect(paint(),'ROLL')
assert(small.healRollBox.y+small.healRollBox.h+3<=298-24,'battle roll extends outside the safe content area')
clock=4
love.touchpressed(1,ui.boxCenter(small.healRollBox))
love.update(1.25)
expect(paint(),'CONTINUE')
assert(small.continueBox.y+small.continueBox.h+3<=298-24,'battle continue extends outside the safe content area')
print('PASS: approved red/blue battle UI, winner-only roll, CPU auto-roll, capped HP, single clean reward banner, tie')
