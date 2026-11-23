package.path = './?.lua;' .. package.path
local r=require('rules')
local function same(a,b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= 'table' then return a==b end
  for k,v in pairs(a) do if not same(v,b[k]) then return false end end
  for k,v in pairs(b) do if a[k]==nil then return false end end
  return true
end
local function eq(a,b,m) assert(a==b,(m or 'mismatch')..': '..tostring(a)..' ~= '..tostring(b)) end
local s=r.new(1234)
eq(#s.units,20,'total soldiers')
eq(r.count(s,1),10);eq(r.count(s,2),10)
eq(s.forts[1].hp,30);eq(s.forts[2].hp,30)
local seen={}
for _,u in ipairs(s.units) do
  local k=r.key(u.r,u.c)
  assert(not seen[k],'overlap starting units')
  seen[k]=true
  eq(r.distance(u,u),0,'self-distance')
  for _,n in ipairs(r.neighbors(u.r,u.c)) do eq(r.distance(u,n),1,'neighbor distance') end
end
for _,f in ipairs(s.forts) do assert(not seen[r.key(f.r,f.c)],'fort overlap') end
local moves=r.moves(s,1)
assert(next(moves),'first Knight must have at least one move')
-- Illegal out-of-turn, jumps, occupied moves and attacks must not mutate state.
local save=r.serialize(s)
local ok,err=r.apply(s,{type='move',id=11,r=0,c=0})
assert(not ok and r.serialize(s)==save)
ok,err=r.apply(s,{type='move',id=1,r=10,c=3})
assert(not ok,'Knight cannot jump onto occupied unit')
assert(r.serialize(s)==save)
ok,err=r.apply(s,{type='attack',id=1,r=1,c=3})
assert(not ok,'Cannot attack distant fort')
-- Across symmetrical opponent positions, all dice and paths must replay deterministically.
local seed=43210
s=r.new(seed)
local first
for k,_ in pairs(r.moves(s,1)) do local rr,cc=r.fromkey(k);first={type='move',id=1,r=rr,c=cc};break end
assert(first)
local ok2,evt=r.apply(s,first)
assert(ok2,evt)
local restored,restoreError=r.restore(r.serialize(s))
assert(restored,restoreError)
assert(same(restored.units,s.units),'save must restore all units')
assert(same(restored.forts,s.forts),'save must restore both Fortresses')
eq(restored.rng,s.rng,'random state restore')
local replayed,err3=r.replay(seed,s.history)
assert(replayed,err3)
eq(r.serialize(replayed),r.serialize(s),'online token replay')
local tokens={}
for i,t in ipairs(s.history) do tokens[i]=t end
assert(not r.replay(seed,{'M2_1_3'}),'invalid move must be rejected')
for _=1,10000 do local x=r.next_random(s,12);assert(x>=1 and x<=12) end
-- Double defeat and Final Siege: construct a legal position with only two 1 HP soldiers.
local t=r.new(88)
for _,u in ipairs(t.units) do
  if u.id~=1 and u.id~=11 then u.hp=0 end
end
local a,b=t.units[1],t.units[11]
a.r,a.c=6,3; b.r,b.c=5,3
assert(r.distance(a,b)==1)
t.turn=1;a.hp=1;b.hp=1
local hit=r.attacks(t,1)
assert(hit[r.key(b.r,b.c)],'adjacent attack available')
local success,combat=r.apply(t,{type='attack',id=1,r=b.r,c=b.c})
assert(success,'mutual-death attack must be legal')
eq(r.count(t,1),0);eq(r.count(t,2),0)
assert(type(combat.siege)=='table' and #combat.siege>0,'auto Final Siege')
assert(t.winner~=nil,'final siege must have an ending')
assert(t.forts[1].hp==0 or t.forts[2].hp==0,'siege must defeat a Fortress')
print('PASS: initial formation, board geometry, blocking, session, online replay, die range, final siege')
