local rules=require('rules')
local boards=require('boards')
local variants=require('variants')
local cpu=require('cpu')
local function count(t)
  local n=0
  for _ in pairs(t) do n=n+1 end
  return n
end

local expected={classic={56,15,3,6},skirmish={37,6,2,3},narrows={68,6,3,2},corners={56,8,4,8},bridges={56,9,4,4},wide={78,15,5,6}}
for _,def in ipairs(boards) do
  local engine=rules.forBoard(def.id)
  local countExpected,troops,default,segments=table.unpack(expected[def.id])
  local hexes=0
  for r=0,engine.ROWS-1 do
    for c=0,engine.COLS-1 do if engine.playable(r,c) then hexes=hexes+1 end end
  end
  assert(hexes==countExpected and variants.defaults(def.id).crateCount==default)
  local opening=rules.new(51,1,{board=def.id})
  assert(#opening.units==2*troops and opening.boardId==def.id)
  for side=1,2 do
    opening.turn=side
    local actions=engine.actions(opening)
    assert(#actions>0)
    for _,act in ipairs(actions) do
      if def.id~='corners' then assert(act.type=='move','No opening-position attack on '..def.id) end
    end
  end
  if def.id=='skirmish' then
    for _,u in ipairs(opening.units) do
      if u.class=='soldier' then assert(u.r==(u.owner==1 and 5 or 1) and u.c==2) end
    end
  elseif def.id=='bridges' then
    for side=1,2 do
      local ogres=0
      for _,u in ipairs(opening.units) do if u.owner==side and u.class=='ogre' then ogres=ogres+1 end end
      assert(ogres==2)
    end
    assert(not engine.playable(4,4))
    local wizard
    for _,u in ipairs(opening.units) do if u.class=='wizard' and u.owner==1 then wizard=u end end
    opening.turn=1
    wizard.r,wizard.c=5,3
    assert(not engine.moves(opening,wizard.id)[engine.key(3,3)],'a wizard cannot bypass the bridges')
    assert(not engine.moves(opening,wizard.id)[engine.key(4,4)],'a wizard cannot land in the gap')
    assert(engine.moves(opening,wizard.id)[engine.key(4,2)],'a wizard can land on the bridge')
    assert(not engine.decode('M'..wizard.id..'_4_4'))
  end
  local outer,upper,lower=false,false,false
  for seed=1,30 do
    for _,wall in ipairs({false,true}) do
      for amount=1,6 do
        local board=rules.new(seed,1,{board=def.id,wall=wall,crates=true,crateCount=amount})
        assert(count(board.crates)==amount and count(board.walls)==(wall and segments or 0))
        for _,section in pairs(board.walls) do assert(engine.playable(section.r,section.c)) end
        for key,crate in pairs(board.crates) do
          assert(engine.playable(crate.r,crate.c) and not engine.occupied(board,crate.r,crate.c))
          assert(not board.walls[key])
          local offset=crate.r-def.middle
          if def.scatteredCrates then
            outer=outer or math.abs(offset)>1
            upper=upper or offset < -1
            lower=lower or offset > 1
          else assert(math.abs(offset)<=1) end
          for k,other in pairs(board.crates) do assert(key==k or engine.distance(crate,other)>1) end
        end
        local restored=assert(rules.restore(engine.serialize(board)))
        assert(restored.boardId==def.id and restored.options.crateCount==amount)
        for key,contents in pairs(restored.crateContents) do assert(board.crateContents[key]==contents) end
      end
    end
  end
  if def.scatteredCrates then assert(outer and upper and lower,'Crates must reach both ends of '..def.name) end
  local completed=0
  for match=1,6 do
    math.randomseed(match*3257)
    local seed=match*991
    local board=rules.new(seed,1+match%2,{board=def.id,wall=match%3==1,crates=match%3~=0})
    for turn=1,360 do
      if board.winner~=nil then break end
      local action=assert(cpu(board,math.random))
      local ok,event=engine.apply(board,action)
      assert(ok,event)
    end
    if board.winner~=nil then completed=completed+1 end
    local restored=assert(rules.restore(engine.serialize(board)))
    assert(restored.rng==board.rng and restored.winner==board.winner and restored.moves==board.moves)
  end
  print(('PASS: %s, 360 crate placements and %d/6 CPU matches completed before the test cutoff'):format(def.name,completed))
end


local narrows=rules.forBoard('narrows-legacy')
local crossed=narrows.new(76,1,{wall=true})
local wizard={r=6,c=0,class='wizard',owner=1}
local target={r=4,c=0,class='wizard',owner=2}
assert(narrows.canAttack(crossed,wizard,target),'a ray outside the wall edge must remain open')
wizard.c,target.c=2,2
assert(not narrows.canAttack(crossed,wizard,target),'a ray across the actual pass must still hit the wall')
crossed.options.overWall=true
assert(narrows.canAttack(crossed,wizard,target))
crossed.options.overWall=false
wizard.c,target.c=1,1
assert(not narrows.canAttack(crossed,wizard,target),'a ray along the outer edge still touches the wall')
wizard.c,target.c=0,0
crossed.replayingNarrows150=true
assert(not narrows.canAttack(crossed,wizard,target),'legacy saves can validate old forced passes')
print('PASS: Narrows walls block rays that intersect a real section, with legacy replay support')


local pass=narrows.new(76,1)
local caster,assassin
for _,u in ipairs(pass.units) do
  if u.owner==1 and u.class=='wizard' then caster=u end
  if u.owner==1 and u.class=='assassin' then assassin=u end
end
caster.r,caster.c=6,0
assert(not narrows.moves(pass,caster.id)[narrows.key(4,0)],'teleport cannot bypass the pass')
caster.c=1
assert(narrows.moves(pass,caster.id)[narrows.key(4,2)],'teleport can cross via a playable middle hex')
caster.c=0
assassin.r,assassin.c=6,1
assert(not narrows.canAttack(pass,assassin,{r=4,c=0,owner=2}),'melee cannot cross the gap')
pass.replayingNarrows150=true
assert(narrows.moves(pass,caster.id)[narrows.key(4,0)],'past local moves can replay using the older rule')
-- Actual 1.5.0 save, including a teleport that is now disallowed during live play.
local old='OPTIONS:B3_0_3_0_16_3_0|v22|76|1|0|0|0|0|M4_7_0,M10_0_0,M4_6_0,M10_0_1,M4_4_0'
local restored=assert(rules.restore(old))
assert(restored.moves==5 and restored.units[4].r==4 and restored.units[4].c==0)
assert(narrows.serialize(restored)==old and restored.replayingNarrows150==nil)
print('PASS: the Narrows requires a playable path for teleport and melee, and restores actual 1.5.0 history')


local bridges=rules.forBoard('bridges')
local closed=bridges.new(76,1,{wall=true,wallHealth=1,wallShield=0})
local row=bridges.board.middle
for _,c in ipairs({1,2,6,7}) do assert(closed.walls[bridges.key(row,c)]) end
local soldier
for _,u in ipairs(closed.units) do
  if u.owner==1 and u.class=='soldier' then soldier=u;break end
end
soldier.r,soldier.c=5,1
local crossing=bridges.key(row,1)
assert(not bridges.moves(closed,soldier.id)[crossing])
assert(bridges.attacks(closed,soldier.id)[crossing].kind=='wall')
assert(bridges.apply(closed,{type='attack',id=soldier.id,r=row,c=1}))
closed.turn=1
assert(closed.walls[crossing].hp==0 and bridges.moves(closed,soldier.id)[crossing])

local legacy='OPTIONS:B4_0_3_1_16_3_0_M4_0|v22|76|1|0|0|0|0|'
local restored=assert(rules.restore(legacy))
assert(count(restored.walls)==2 and bridges.serialize(restored)==legacy)
local current=bridges.new(76,1,{wall=true,crates=true})
local saved=bridges.serialize(current)
assert(saved:match('^OPTIONS:B6_'))
assert(count(assert(rules.restore(saved)).walls)==4)
print('PASS: both Twin Bridges lanes require a breach, with older partial-wall saves preserved')

local narrowed=rules.forBoard('narrows')
local corners=rules.forBoard('corners')
local passCells={[3]=true,[4]=true}
for c=0,7 do assert(not not narrowed.playable(5,c)==not not passCells[c]) end
for _,r in ipairs({4,6}) do
  for _,c in ipairs({1,7}) do assert(narrowed.playable(r,c)) end
end
local sealed=narrowed.new(1,1,{wall=true})
for _,c in ipairs({3,4}) do assert(sealed.walls[narrowed.key(5,c)]) end
assert(variants.encode(sealed.options):match('^B7_'))
assert(variants.decode('B3_0_3_0_16_3_0').board=='narrows-legacy')

local opening=corners.new(1,1)
for side=1,2 do
  local col=side+2
  assert(opening.forts[side].r==5 and opening.forts[side].c==col)
  for _,check in ipairs({{3,'ogre'},{7,'soldier'}}) do
    local piece=corners.occupied(opening,check[1],col).ref
    assert(piece.class==check[2] and piece.owner==side)
  end
end
for _,cell in ipairs({{2,1},{2,6},{8,0},{8,5}}) do
  assert(not corners.occupied(opening,cell[1],cell[2]))
end
local ring=corners.new(1,1,{wall=true,wallHealth=1,wallShield=0})
for _,fort in ipairs(ring.forts) do
  for _,near in ipairs(corners.neighbors(fort.r,fort.c)) do
    local occupant=corners.occupied(ring,near.r,near.c)
    assert(occupant and (occupant.kind=='wall' or occupant.kind=='fort'))
  end
end
local archer={r=5,c=0,class='archer',owner=2}
local wizard={r=3,c=3,class='wizard',owner=1}
assert(not corners.canAttack(ring,archer,ring.forts[1]),'lateral ring section stops a shot')
assert(not corners.canAttack(ring,wizard,ring.forts[2]),'upper ring section stops a spell')
ring.options.overWall=true
assert(corners.canAttack(ring,archer,ring.forts[1]))
assert(corners.canAttack(ring,wizard,ring.forts[2]))
ring.options.overWall=false
ring.walls[corners.key(5,2)].hp=0
assert(corners.canAttack(ring,archer,ring.forts[1]))
assert(not corners.canAttack(ring,wizard,ring.forts[2]))
assert(variants.encode(ring.options):match('^B8_'))
assert(not variants.decode('B9_0_3_0_16_3_0'))
print('PASS: marked Narrows footprint, annotated Four Corners positions, full ring, and breached line of fire')

-- A Four Corners save from 1.5.3 uses the earlier center-focused placement.
local earlier='OPTIONS:B8_0_3_1_16_3_0_M4_1|v22|443|1|0|0|0|0|'
local saved=assert(rules.restore(earlier))
assert(corners.serialize(saved)==earlier)
for _,crate in pairs(saved.crates) do assert(math.abs(crate.r-5)<=1) end
local scattered=corners.new(443,1,{wall=true,crates=true,destroyCrates=true})
assert(corners.serialize(scattered):find('_G4_1|',1,true))
assert(not variants.decode('0_3_0_16_3_0_G4_1'))
print('PASS: old save placement and wire marker preserved alongside whole-board crate distribution')
