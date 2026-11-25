package.path='./?.lua;'..package.path
local saved,texts={},{}
local now=0
local labels,rectangles={},{}
local currentFont
local draws=0
local fortressSprites=0
local portraitSprites=0
local maskCalls=0
love={graphics={},timer={getTime=function()return now end},math={random=function(a,b)
  if a and b then return math.random(a,b) elseif a then return math.random(a) else return math.random() end end},
 filesystem={createDirectory=function()return true end,getInfo=function(k)return saved[k] and {type='file'} end,
  write=function(k,v)saved[k]=v;return true end,read=function(k)return saved[k] end,
  remove=function(k)saved[k]=nil;return true end}}
local g=love.graphics
for _,name in ipairs({'setColor','setFont','polygon','setLineWidth','circle','line'}) do g[name]=function(...) end end
g.rectangle=function(mode,x,y,w,h)
  if mode=='line' then rectangles[#rectangles+1]={x=x,y=y,w=w,h=h} end
end
g.setFont=function(font)currentFont=font end
g.printf=function(t,x,y,w)
  texts[#texts+1]=tostring(t)
  labels[t]={x=x,y=y,w=w,h=currentFont.size}
end
g.newFont=function(size)assert(size>=11);return {size=size} end
-- Mock the host stencil API to exercise badge-only clipping.
g.stencil=function(fn,action,value)maskCalls=maskCalls+1;fn()end
g.setStencilTest=function(...)end
g.newImage=function(path)
  local w,h=path=='art/board.png' and 700 or 144,path=='art/board.png' and 984 or 144
  if path:find('^portraits/') then w,h=240,240 end
  return {path=path,getDimensions=function()return w,h end,
    getWidth=function()return w end,setFilter=function()end}
end
g.draw=function(img,...)
 draws=draws+1
 if img and img.path and img.path:find('^art/fortress%-') then
   fortressSprites=fortressSprites+1
 end
 if img and img.path and img.path:find('^portraits/') then
   portraitSprites=portraitSprites+1
 end
end
local width,height=390,700
g.getDimensions=function()return width,height end
package.preload.zompa=function()return {mode=function()return 'solo',false end,
 saveSession=function(v)saved.session=v;return true end,
 loadSession=function()return saved.session end,clearSession=function()saved.session=nil;return true end,
 audio=function()return {update=function()end}end}end
local rules=require('rules')
local ui=require('tests.ui_geometry')
dofile('main.lua');love.load()
local function paint() texts,labels,rectangles={},{},{};draws=0;love.draw();return table.concat(texts,' ') end
local function tapXY(x,y) now=now+.17; love.touchpressed(1,x,y) end
local function tapCell(r,c) tapXY(ui.cell(love,r,c)) end
local function tapButton(name)
  paint()
  tapXY(ui.boxCenter(ui.button(love,name)))
end
local function tapConfirm() tapButton('actionBox') end
local function tapCancel() tapButton('cancelBox') end
local function has(t,word) assert(t:find(word,1,true),'missing '..word..' in '..t:sub(1,700)) end
local function getState()
  for i=1,60 do local name,val=debug.getupvalue(love.draw,i)
    if name=='state' then return val end if not name then break end end
  error('game state inaccessible for UI test')
end
local state=getState()
local idle=paint()
has(idle,'CHOOSE A PIECE')
assert(draws>=30,'all 30 living piece sprites must render')
assert(fortressSprites==2,'both fortress sprite assets must render on board')
-- A Fortress can be inspected before choosing a troop.
tapCell(state.forts[2].r,state.forts[2].c)
has(paint(),'BLUE FORTRESS')
assert(state.moves==0)
-- Inspect the opponent: does not spend a turn.
tapCell(2,1)
has(paint(),'ASSASSIN')
assert(maskCalls>0,'inspection should mask the original square tile background')
assert(state.turn==1 and state.moves==0)
-- Inspect a friendly player; the clear unit stats must be visible.
tapCell(7,1)
local info=paint()
for _,v in ipairs({'RED SOLDIER','HEALTH 22 / 22','MOVE 1','HIT 5'}) do has(info,v) end
assert(portraitSprites>0,'red side-view portrait must be used in live unit card')
assert(not info:find('P1',1,true) and not info:find('MARCH',1,true),'old P1/MARCH card leaked')
assert(not info:find('CAPTURE RANGE',1,true))
-- Each Fortress overrides the troop card while leaving that troop selected.
tapCell(6,1)
has(paint(),'MOVE HERE')
state.forts[2].hp=42
tapCell(state.forts[2].r,state.forts[2].c)
local blueFort=paint()
has(blueFort,'BLUE FORTRESS')
has(blueFort,'HEALTH 42 / 50')
has(blueFort,'DEFENSE HIT 5')
assert(not blueFort:find('RED SOLDIER',1,true))
assert(not blueFort:find('ATTACK NOW',1,true) and not blueFort:find('MOVE HERE',1,true))
tapCell(state.forts[1].r,state.forts[1].c)
local redFort=paint()
has(redFort,'RED FORTRESS')
has(redFort,'HEALTH 50 / 50')
has(redFort,'DEFENSE HIT 5')
assert(state.turn==1 and state.moves==0,'inspecting a Fortress must not spend a turn')
state.forts[2].hp=50
-- Tapping a glowing empty cell previews. It must not commit until the Move button.
tapCell(6,1)
has(paint(),'MOVE HERE')
assert(state.turn==1 and state.moves==0)
tapCancel()
assert(state.moves==0)
tapCell(6,1);tapConfirm()
assert(state.turn==2 and state.moves==1)
assert(saved.session,'must save immediately even during movement animation')
local advancing=paint()
has(advancing,'RED KINGDOM MOVES')
love.update(1.1)
paint()
-- Create a controlled battle to check the animation, outcome and readable dice.
for _,u in ipairs(state.units) do if u.id~=8 and u.id~=23 then u.hp=0 end end
local a,b=state.units[8],state.units[23]
a.r,a.c,a.hp=5,2,14;b.r,b.c,b.hp=4,2,14
state.turn,state.moves,state.last,state.winner=1,1,nil,nil
tapCell(5,2)
has(paint(),'ASSASSIN')
tapCell(4,2)
has(paint(),'ATTACK NOW')
assert(state.moves==1 and a.hp==14 and b.hp==14,'preview cannot start battle')
local rng=state.rng
local savedBefore=saved.session
tapConfirm()
has(paint(),'RED KINGDOM MOVES')
assert(draws>=2,'attacker must travel OVER the still-visible defender')
love.update(1.05)
has(paint(),'BATTLE')
love.update(60)
local choice=paint()
has(choice,'ROLL')
has(choice,'FLEE')
assert(not choice:find('ROLLING',1,true),'dice must wait for Roll')
local battle=ui.upvalue(love.draw,'overlay')
assert(battle.attackRollBox.x+battle.attackRollBox.w<battle.fleeBox.x)
tapXY(ui.boxCenter(battle.fleeBox))
has(paint(),'ATTACK CANCELED')
love.update(1)
assert(not paint():find('BATTLE',1,true),'Flee must return to board')
assert(state.turn==1 and state.moves==1 and state.rng==rng and saved.session==savedBefore)
assert(a.r==5 and a.c==2 and a.hp==14 and b.hp==14)
tapCell(5,2)
tapCell(4,2)
tapConfirm()
love.update(1.05)
has(paint(),'FLEE')
battle=ui.upvalue(love.draw,'overlay')
tapXY(ui.boxCenter(battle.attackRollBox))
assert(state.moves==2 and state.rng~=rng,'Roll commits exactly one battle')
local started=paint()
has(started,'ROLLING')
assert(not started:find('FLEE',1,true),'Flee is only offered before rolling')
-- Modal input must be blocked while battle is playing.
tapCell(7,0)
assert(state.moves==2)
love.update(1.18)
local revealed=paint()
has(revealed,'ROUND')
love.update(1.00)
local impact=paint()
-- Sample short battle phases instead of jumping across several exchanges.
-- Each hit cue is intentionally brief in the new polished presentation.
for _=1,180 do
  if impact:find(' HITS!',1,true) then break end
  love.update(.12);impact=paint()
end
has(impact,' HITS!')
-- The last exchange holds its impact briefly, then shows the full result.
love.update(70)
local finished=paint()
assert(finished:find('ROLL',1,true) or finished:find('HEALTH BONUS',1,true),
  'a finished battle must offer the deterministic winner reward')
assert(not finished:find('ROLL FOR +1 TO +8 HP',1,true),'old verbose button remains')
assert(not finished:find('HEALTH BONUS +4 HP',1,true),'bonus must not append HP')
-- In solo games Red rolls manually. The Blue CPU rolls automatically.
local rollBox=ui.upvalue(love.draw,'overlay').healRollBox
if rollBox then
  tapXY(ui.boxCenter(rollBox))
  local rolling=paint()
  assert(not rolling:find('RED ROLLS FOR VICTORY BONUS',1,true),
    'the victory prompt must disappear when the single die starts')
end
love.update(1.20)
finished=paint()
assert(finished:find('HEALTH BONUS +',1,true) or finished:find('HEALTH FULL',1,true),
  'bonus result must be prominent')
has(finished,'CONTINUE')
local latest=state.last
assert(latest.heal and latest.heal.roll>=1 and latest.heal.roll<=8)
assert(latest.heal.actual>=0 and latest.heal.actual<=latest.heal.roll)
tapXY(ui.boxCenter(ui.upvalue(love.draw,'overlay').continueBox))
assert(not paint():find('BATTLE',1,true),'continue should dismiss combat')
-- Verify controls and card text against both the viewport and its safe area.
state.units=rules.new(47061).units
love.window={getSafeArea=function() return 0,0,width,height-20 end}
for _,dim in ipairs({{240,320},{280,480},{320,520},{420,850},{390,700},{450,980}}) do
  width,height=dim[1],dim[2]
  love.resize(width,height)
  state.turn=1
  tapCell(7,1)
  tapCell(6,1)
  has(paint(),'MOVE HERE')
  local layout=ui.layout(love)
  local move,hit=labels['MOVE 1'],labels['HIT 5']
  local band
  for _,box in ipairs(rectangles) do
    if box.h==layout.moveBandH and box.y<=move.y and box.x<=move.x then band=box;break end
  end
  assert(hit and band,'missing live stat band')
  assert(move.y-band.y>=5 and band.y+band.h-hit.y-hit.h>=5,'stat text touches its border')
  assert(layout.cardY+layout.cardH-band.y-band.h>=7,'stat band touches the outer card')
  assert(layout.cardY+layout.cardH<layout.y,'card overlaps the board')
  for _,name in ipairs({'actionBox','cancelBox'}) do
    local button=ui.button(love,name)
    assert(button.y-3>layout.y+layout.boardH,'button frame overlaps the board')
    assert(button.y+button.h+3<=height-20-24,'button frame enters the bottom safety margin')
  end
  tapCancel()
end
-- In range, the enemy Fortress is inspected and still offers a confirmed attack.
for _,u in ipairs(state.units) do u.hp=0 end
local wizard=state.units[3]
wizard.r,wizard.c,wizard.hp=2,2,24
local fort=state.forts[2]
tapCell(wizard.r,wizard.c)
tapCell(fort.r,fort.c)
local attackFort=paint()
has(attackFort,'BLUE FORTRESS')
has(attackFort,'ATTACK NOW')
assert(state.moves==2,'previewing a Fortress attack must not spend a turn')
-- Let the CPU begin a fight on the final rank and wait at the defender's Roll prompt.
for _,u in ipairs(state.units) do u.hp=0 end
local cpu=state.units[28]
cpu.r,cpu.c,cpu.hp=9,0,22
local guard=state.units[1]
guard.r,guard.c,guard.hp=10,0,32
state.turn=2
love.update(2)
love.update(2)
love.update(60)
local defending=paint()
has(defending,'BATTLE')
has(defending,'ROLL')
assert(not defending:find('FLEE',1,true) and not defending:find('ROLLING',1,true))
local defense=ui.upvalue(love.draw,'overlay')
tapXY(ui.boxCenter(defense.attackRollBox))
has(paint(),'ROLLING')
print('PASS: incoming CPU battle waits for defender Roll')
print('PASS: Fortress inspection before selection, after a move preview and during an attack preview')
print('PASS: touch-aligned action buttons and padded stats at six portrait heights, including a simulated bottom inset')
