local rules=require('rules')
local variants=require('variants')
local choose=require('cpu')
local function size(items)
  local n=0
  for _ in pairs(items) do n=n+1 end
  return n
end

local mixes={}
for seed=1,100 do
  for _,count in ipairs({1,3,9}) do
    local options={crates=true,crateCount=count,destroyCrates=seed%2==0,wall=seed%3~=0}
    local board=rules.new(seed,1,options)
    local replay=assert(rules.restore(rules.serialize(board)))
    assert(size(board.crates)==count and size(board.crateContents)==count)
    assert(not next(board.traps) and not next(board.potions) and not next(board.scorches))
    local bombs=0
    for key,crate in pairs(board.crates) do
      assert(not board.walls[key] and math.abs(crate.r-variants.row)<=1)
      assert(replay.crateContents[key]==board.crateContents[key])
      assert(replay.crates[key] and replay.crates[key].c==crate.c)
      assert(crate.contents==nil)
      if board.crateContents[key]=='bomb' then bombs=bombs+1 end
    end
    if count==9 then mixes[bombs]=true end
  end
end
assert(size(mixes)>=4,'the mix should vary across seeds')
assert(not variants.decode('1_3_1_16_3_0_C6_0'),'legacy traps cannot be enabled alongside crates')
assert(not variants.decode('0_3_0_16_3_0_C0_0'))
assert(variants.decode('1_3_0_16_3_0_2_1').potions,'old options must still decode')

local key=rules.key(5,1)
local function fixture(contents,hp)
  local board=rules.new(81,1,{crates=true,crateCount=1})
  board.crates={[key]={r=5,c=1}}
  board.crateContents={[key]=contents}
  local unit=board.units[3]
  unit.r,unit.c,unit.hp=6,1,hp
  return board,unit
end
for _,contents in ipairs({'potion','bomb'}) do
  local board,unit=fixture(contents,contents=='potion' and 3 or 16)
  local oldHp=unit.hp
  local ok,event=rules.apply(board,{type='move',id=unit.id,r=5,c=1})
  assert(ok and event.crate.contents==contents and not event.crate.destroyed)
  assert(unit.hp==oldHp+(contents=='potion' and 12 or -12))
  assert(board.crates[key]==nil and board.crateContents[key]==nil)
  assert(board.scorches[key]==(contents=='bomb' and true or nil))
  board,unit=fixture(contents,18)
  local shot={type='crate',id=unit.id,r=5,c=1}
  assert(not rules.apply(board,shot),'setting off must reject shots')
  board.options.destroyCrates=true
  local soldier=board.units[12]
  soldier.r,soldier.c=6,2
  assert(not rules.apply(board,{type='crate',id=soldier.id,r=5,c=1}),'melee cannot shoot crates')
  ok,event=rules.apply(board,shot)
  assert(ok and event.crate.destroyed and event.crate.contents==contents)
  assert(board.scorches[key] and not board.crates[key] and unit.hp==18)
  assert(rules.decode(board.history[1]).type=='crate')
end
local board,unit=fixture('potion',15)
assert(rules.apply(board,{type='move',id=unit.id,r=5,c=1}))
assert(unit.hp==18 and not board.crates[key],'potion is capped and one-use')
board,unit=fixture('bomb',12)
assert(rules.apply(board,{type='move',id=unit.id,r=5,c=1}))
assert(unit.hp==0 and board.scorches[key])

for seed=1,32 do
  local board=rules.new(seed,2,{crates=true,crateCount=9,destroyCrates=true,wall=seed%2==0})
  board.units[18].r,board.units[18].c,board.units[18].hp=4,0,6
  local function random()return .25 end
  local action=rules.encode(choose(board,random))
  local function hidden()error('CPU tried to read crate contents')end
  board.crateContents=setmetatable({},{__index=hidden,__pairs=hidden,__len=hidden})
  assert(rules.encode(choose(board,random))==action)
end
print('PASS: max-count generation, fixed effects, ranged destruction, scorch, legacy options, and hidden-content fairness')
