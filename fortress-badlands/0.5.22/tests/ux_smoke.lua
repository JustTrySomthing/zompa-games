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
local opening=ui.upvalue(love.draw,'overlay')
assert(opening.type=='opening')
assert(opening.opening.first==ui.upvalue(love.draw,'state').turn)
local function paint() texts,labels,rectangles={},{},{};draws,fortressSprites=0,0;love.draw();return table.concat(texts,' ') end
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
love.update(100)
local intro=paint()
for _,label in ipairs({'ROLL','You','CPU','Red','Blue'}) do has(intro,label) end
assert(opening.elapsed==nil,'opening must wait for the player')
tapXY(ui.boxCenter(opening.button))
assert(opening.elapsed==0)
love.update(100)
has(paint(),(state.turn==1 and 'Red' or 'Blue').."'s Turn")
state.turn=1
love.update(1.1)
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
for _,v in ipairs({'RED SOLDIER','HEALTH 16 / 16','MOVE 1','POWER 8','SHIELD 2'}) do has(info,v) end
assert(portraitSprites>0,'red side-view portrait must be used in live unit card')
assert(not info:find('P1',1,true) and not info:find('MARCH',1,true),'old P1/MARCH card leaked')
assert(not info:find('CAPTURE RANGE',1,true))
-- Each Fortress overrides the troop card while leaving that troop selected.
tapCell(6,1)
has(paint(),'MOVE HERE')
state.forts[2].hp=22
tapCell(state.forts[2].r,state.forts[2].c)
local blueFort=paint()
has(blueFort,'BLUE FORTRESS')
has(blueFort,'HEALTH 22 / 30')
has(blueFort,'POWER 8')
assert(not blueFort:find('RED SOLDIER',1,true))
assert(not blueFort:find('ATTACK NOW',1,true) and not blueFort:find('MOVE HERE',1,true))
tapCell(state.forts[1].r,state.forts[1].c)
local redFort=paint()
has(redFort,'RED FORTRESS')
has(redFort,'HEALTH 30 / 30')
has(redFort,'POWER 8')
assert(state.turn==1 and state.moves==0,'inspecting a Fortress must not spend a turn')
state.forts[2].hp=30
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
has(paint(),"Blue's Turn")
love.update(1.1)
paint()
-- Confirming an attack starts the battle sequence and spends one turn.
for _,u in ipairs(state.units) do if u.id~=8 and u.id~=23 then u.hp=0 end end
local a,b=state.units[8],state.units[23]
a.r,a.c,a.hp=4,1,10;b.r,b.c,b.hp=4,2,10
state.turn,state.moves,state.last,state.winner=1,1,nil,nil
state.rng=1
tapCell(4,1);tapCell(4,2)
tapConfirm()
love.update(.21)
has(paint(),'Red Assassin Attacks')
has(paint(),'Blue Assassin')
love.update(1.33)
love.update(.35)
has(paint(),'Ready for Combat')
has(paint(),'D12')
local battle=ui.upvalue(love.draw,'overlay')
assert(not battle.button,'Ready for Combat should be hands-free')
assert(state.moves==2 and a.c==1)
love.update(.85)
has(paint(),'ATTACK ROLL')
assert(not battle.button)
love.update(3.5)
has(paint(),'VICTORY')
has(paint(),'Bonus Roll')
assert(not battle.button)
love.update(2)
has(paint(),'CONTINUE')
assert(ui.layout(love).h-4-(battle.button.y+battle.button.h+3)>=11,
  'Continue frame needs padding inside the battle panel')
tapXY(ui.boxCenter(battle.button))
has(paint(),"Blue's Turn")
love.update(1.1)
paint()
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
  local move,hit=labels['MOVE 1'],labels['POWER 8']
  local band
  for _,box in ipairs(rectangles) do
    if box.h==layout.moveBandH and box.y<=move.y and box.x<=move.x then band=box;break end
  end
  assert(hit and band,'missing live stat band')
  assert(move.y-band.y>=4.99 and band.y+band.h-hit.y-hit.h>=4.99,'stat text touches its border')
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
wizard.r,wizard.c,wizard.hp=1,1,18
local fort=state.forts[2]
tapCell(wizard.r,wizard.c)
tapCell(fort.r,fort.c)
local attackFort=paint()
has(attackFort,'BLUE FORTRESS')
has(attackFort,'ATTACK NOW')
assert(state.moves==2,'previewing a Fortress attack must not spend a turn')
print('PASS: responsive stat cards, selected target previews and player attack/bonus controls')
