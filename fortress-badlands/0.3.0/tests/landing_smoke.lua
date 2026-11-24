package.path='./?.lua;'..package.path
local rules=require('rules')
local function reset(attacker,enemy,r,c,er,ec)
  local s=rules.new(11732)
  for _,unit in ipairs(s.units) do unit.hp=0 end
  local a=s.units[attacker];local b=s.units[enemy]
  a.r,a.c,a.hp=r,c,rules.classes[a.class].hp
  b.r,b.c,b.hp=er,ec,rules.classes[b.class].hp
  s.turn=1
  return s,a,b
end
local cases={
  {id=1,steps=3}, -- Knight
  {id=4,steps=2}, -- Warrior
  {id=3,steps=2}, -- Archer
  {id=5,steps=1}, -- Wizard
  {id=8,steps=1}, -- Barbarian
}
for _,case in ipairs(cases) do
  local s,a,b=reset(case.id,11,6,3,6,3+case.steps)
  local k=rules.key(b.r,b.c)
  assert(rules.distance(a,b)==case.steps,'bad test distance')
  assert(rules.attacks(s,a.id)[k],a.class..' should attack by moving '..case.steps..' hexes')
  assert(rules.moves(s,a.id)[k]==nil,'enemy cannot be an empty move')
  local path=assert(rules.route(s,a.id,b.r,b.c))
  assert(#path==case.steps+1,'path should have one cell per movement step')
  for i=2,#path do assert(rules.distance(path[i-1],path[i])==1) end
  assert(not rules.apply(s,{type='move',id=a.id,r=b.r,c=b.c}),'occupied enemy hex is ATTACK only')
  local far=reset(case.id,11,6,2,6,2+case.steps+1)
  assert(not rules.attacks(far,case.id)[rules.key(6,2+case.steps+1)],a.class..' must not attack past Move')
end
-- Soldiers cannot jump over an occupied hex. Fill all 8 neighboring squares.
local s,a,b=reset(1,11,6,3,4,3)
local blockCount=0
for _,pos in ipairs(rules.neighbors(a.r,a.c)) do
  blockCount=blockCount+1
  local u=s.units[blockCount+1]
  u.hp=rules.classes[u.class].hp
  u.owner=1;u.r=pos.r;u.c=pos.c
end
assert(blockCount==8)
assert(not rules.attacks(s,a.id)[rules.key(b.r,b.c)])
assert(not rules.route(s,a.id,b.r,b.c))
-- A soldier cannot hit merely by standing next to an enemy: it must target enemy hex.
local s,a,b=reset(3,11,6,3,5,3)
local hp=a.hp..':'..b.hp
local empty
for k in pairs(rules.moves(s,a.id)) do
  local r,c=rules.fromkey(k)
  if rules.distance({r=r,c=c},b)==1 then empty={r=r,c=c};break end
end
assert(empty)
local ok,event=rules.apply(s,{type='move',id=a.id,r=empty.r,c=empty.c})
assert(ok and event.type=='move' and a.hp..':'..b.hp==hp)
assert(b.hp>0,'adjacency is not an automatic battle')
-- Empty and enemy destination use the same movement budget; winner occupies target.
local s,a,b=reset(1,11,6,3,6,6)
local target={r=b.r,c=b.c}
assert(rules.attacks(s,1)[rules.key(b.r,b.c)])
assert(not rules.apply(s,{type='attack',id=1,r=6,c=0}))
local ok,event=rules.apply(s,{type='attack',id=1,r=target.r,c=target.c})
assert(ok and event.type=='attack')
if a.hp>0 then assert(a.r==target.r and a.c==target.c and b.hp==0) end
if b.hp>0 then assert(a.hp==0 and b.r==target.r and b.c==target.c) end
local clean=rules.new(11732)
local legal=rules.moves(clean,1)
local first=next(legal)
assert(first)
local rr,cc=rules.fromkey(first)
assert(rules.apply(clean,{type='move',id=1,r=rr,c=cc}))
local saved=rules.serialize(clean)
assert(saved:sub(1,3)=='v3|')
assert(not rules.restore(saved:gsub('^v3|','v1|')),'legacy saves must not replay under new rules')
local restored,err=rules.restore(saved);assert(restored,err)
assert(restored.units[1].r==clean.units[1].r and restored.units[1].c==clean.units[1].c)
print('PASS: universal MOVE reach for attacking, legal routes, blocked paths, no auto-battles, replay v3')
