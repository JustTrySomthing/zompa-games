package.path='./?.lua;'..package.path
local r=require('rules')
local function eq(a,b,name) assert(a==b,(name or 'mismatch')..': '..tostring(a)..' ~= '..tostring(b)) end
local function same(a,b)
  if type(a)~=type(b) then return false end
  if type(a)~='table' then return a==b end
  for k,v in pairs(a) do if not same(v,b[k]) then return false end end
  for k in pairs(b) do if a[k]==nil then return false end end
  return true
end
local state=r.new(1234)
eq(#state.units,20);eq(r.count(state,1),10);eq(r.count(state,2),10)
eq(r.FORT_HP,35);eq(r.FORT_DIE,8);eq(r.FORT_HIT,5)
eq(r.SIEGE_DIE,8);eq(r.SIEGE_HIT,7)
for _,class in pairs(r.classes) do assert(class.die==nil and class.attack==nil);assert(class.hit==5 or class.hit==7) end
eq(r.classes.knight.hp,15)
local seen={}
for _,u in ipairs(state.units) do
  local key=r.key(u.r,u.c);assert(not seen[key]);seen[key]=true
  eq(r.distance(u,u),0)
  for _,near in ipairs(r.neighbors(u.r,u.c)) do eq(r.distance(u,near),1) end
end
for _,f in ipairs(state.forts) do assert(not seen[r.key(f.r,f.c)]) end
assert(next(r.moves(state,1)))
local saved=r.serialize(state)
assert(not r.apply(state,{type='move',id=11,r=0,c=0}))
assert(not r.apply(state,{type='move',id=1,r=10,c=3}))
assert(not r.apply(state,{type='attack',id=1,r=0,c=3}))
eq(r.serialize(state),saved)

local foundWins={attacker=false,defender=false,tie=false}
for seed=1,300 do
  local s=r.new(seed)
  -- Isolated attack without ending the game or triggering the Final Siege.
  for _,u in ipairs(s.units) do if u.id~=1 and u.id~=11 then u.hp=0 end end
  local u,v=s.units[1],s.units[11]
  u.r,u.c=6,3;v.r,v.c=5,3
  u.hp=15;v.hp=15
  s.turn=1
  local at={type='attack',id=1,r=v.r,c=v.c}
  assert(r.attacks(s,1)[r.key(v.r,v.c)],'adjacent enemy tap must be legal')
  local target={r=v.r,c=v.c};local from={r=u.r,c=u.c}
  local ok,e=r.apply(s,at);assert(ok,e)
  assert(e.attackerHpEnd>0 or e.defenderHpEnd>0,'no simultaneous soldier death')
  assert(not (e.attackerHpEnd==0 and e.defenderHpEnd==0))
  for _,roll in ipairs(e.rounds) do
    assert(roll.a>=1 and roll.a<=8 and roll.b>=1 and roll.b<=8)
    if roll.a==roll.b then
      assert(roll.who=='tie' and roll.damage==0)
      foundWins.tie=true
    elseif roll.a>roll.b then
      assert(roll.who=='attacker' and roll.damage==r.classes[u.class].hit)
    else
      assert(roll.who=='defender' and roll.damage==r.classes[v.class].hit)
    end
  end
  if u.hp>0 then
    foundWins.attacker=true
    assert(e.captured,'winning attacker captures hex')
    eq(u.r,target.r);eq(u.c,target.c)
    assert(v.hp==0)
  else
    foundWins.defender=true
    eq(v.r,target.r);eq(v.c,target.c)
    eq(u.r,from.r);eq(u.c,from.c)
  end
  assert(e.heal and e.heal.roll>=4 and e.heal.roll<=10,'winner healing')
end
assert(foundWins.attacker and foundWins.defender and foundWins.tie,'win, loss and tie rolls covered')

-- Fortress protection: retaliatory D8 winner applies 5, never heals.
local fortressTest=r.new(7788)
for _,u in ipairs(fortressTest.units) do if u.id~=1 then u.hp=0 end end
local hero=fortressTest.units[1];hero.r,hero.c=1,3;hero.hp=15
fortressTest.forts[2].hp=5
assert(r.attacks(fortressTest,1)[r.key(0,3)],'fortress must be attackable')
local ok,fe=r.apply(fortressTest,{type='attack',id=1,r=0,c=3})
assert(ok,fe)
for _,v in ipairs(fe.rounds) do
  if v.who=='defender' then eq(v.damage,5,'fortress fixed hit') end
end
if fe.defenderHpEnd==0 then eq(fortressTest.winner,1) end
assert(fortressTest.forts[2].hp<=5,'fortress cannot heal')

-- Destroy both armies through final soldier's attack against an otherwise undefended fortress.
local siegeSeen={mutual=false,victory=false}
for seed=1,1000 do
  local t=r.new(seed)
  for _,u in ipairs(t.units) do if u.id~=1 then u.hp=0 end end
  t.turn=1
  local unit=t.units[1];unit.r,unit.c=1,3;unit.hp=1
  t.forts[1].hp=7;t.forts[2].hp=20
  local ok,event=r.apply(t,{type='attack',id=1,r=0,c=3})
  assert(ok,event)
  if t.count==0 then error('invalid count') end
  if unit.hp==0 then
    assert(event.siege and #event.siege>0,'automatic final siege')
    for _,volley in ipairs(event.siege) do
      local hit1=volley.a>=4 and 7 or 0
      local hit2=volley.b>=4 and 7 or 0
      eq(volley.hit1,hit1);eq(volley.hit2,hit2)
    end
    assert(t.winner~=nil)
    siegeSeen.victory=true
    if t.winner==0 then siegeSeen.mutual=true end
  end
  if siegeSeen.mutual and siegeSeen.victory then break end
end
assert(siegeSeen.victory and siegeSeen.mutual,'siege must permit simultaneous destruction')

-- Deterministic action logs must replay the same dice and coordinates on both phones.
local seed=43210
local s=r.new(seed)
local first
for k in pairs(r.moves(s,1)) do local rr,cc=r.fromkey(k);first={type='move',id=1,r=rr,c=cc};break end
assert(first)
assert(r.apply(s,first))
local replay,err=r.restore(r.serialize(s));assert(replay,err)
assert(same(s.units,replay.units));assert(same(s.forts,replay.forts))
eq(s.rng,replay.rng)
assert(not r.replay(seed,{'M2_1_3'}),'invalid online token')
for i=1,2000 do local n=r.next_random(s,8);assert(n>=1 and n<=8) end
print('PASS: formations, moves, combat, unique winners, capture, fortress, siege, heal, replay')
