local rules=require('rules')
local boards=require('boards')
local variants=require('variants')
local cpu=require('cpu')
local function count(t)
  local n=0
  for _ in pairs(t) do n=n+1 end
  return n
end

local expected={classic={56,15,3,6},skirmish={37,6,2,3},narrows={60,9,3,2},bridges={56,9,4,2},wide={78,15,5,6}}
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
    for _,act in ipairs(actions) do assert(act.type=='move','No opening-position attack on '..def.id) end
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
  for seed=1,30 do
    for _,wall in ipairs({false,true}) do
      for amount=1,6 do
        local board=rules.new(seed,1,{board=def.id,wall=wall,crates=true,crateCount=amount})
        assert(count(board.crates)==amount and count(board.walls)==(wall and segments or 0))
        for _,section in pairs(board.walls) do assert(engine.playable(section.r,section.c)) end
        for key,crate in pairs(board.crates) do
          assert(engine.playable(crate.r,crate.c) and not engine.occupied(board,crate.r,crate.c))
          assert(not board.walls[key] and math.abs(crate.r-def.middle)<=2)
          for k,other in pairs(board.crates) do assert(key==k or engine.distance(crate,other)>1) end
        end
        local restored=assert(rules.restore(engine.serialize(board)))
        assert(restored.boardId==def.id and restored.options.crateCount==amount)
        for key,contents in pairs(restored.crateContents) do assert(board.crateContents[key]==contents) end
      end
    end
  end
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
