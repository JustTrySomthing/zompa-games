package.path='./?.lua;'..package.path
local r=require('rules')
local function eq(a,b) assert(a==b,tostring(a)..' ~= '..tostring(b)) end
local s=r.new(1234)
eq(#s.units,20);eq(r.count(s,1),10);eq(r.count(s,2),10)
eq(r.FORT_HP,35);eq(r.FORT_DIE,8);eq(r.FORT_HIT,5)
eq(r.SIEGE_DIE,8);eq(r.SIEGE_HIT,7)
for _,c in pairs(r.classes) do assert(c.die==nil and c.attack==nil);assert(c.hit==5 or c.hit==7) end
eq(r.classes.knight.hp,15)
local seen={}
for _,u in ipairs(s.units) do
  local key=r.key(u.r,u.c)
  assert(not seen[key]);seen[key]=true
  eq(r.distance(u,u),0)
  for _,n in ipairs(r.neighbors(u.r,u.c)) do eq(r.distance(u,n),1) end
end
for _,f in ipairs(s.forts) do assert(not seen[r.key(f.r,f.c)]) end
assert(next(r.moves(s,1)))
local old=r.serialize(s)
assert(not r.apply(s,{type='move',id=11,r=0,c=0}))
assert(not r.apply(s,{type='move',id=1,r=10,c=3}))
assert(not r.apply(s,{type='attack',id=1,r=1,c=3}))
eq(r.serialize(s),old)
local found={attacker=false,defender=false,tie=false}
for seed=1,300 do
  local match=r.new(seed)
  for _,unit in ipairs(match.units) do if unit.id~=1 and unit.id~=11 then unit.hp=0 end end
  local u,v=match.units[1],match.units[11]
  u.r,u.c=6,3;v.r,v.c=5,3
  u.hp=15;v.hp=15;match.turn=1
  local from={r=u.r,c=u.c}
  local target={r=v.r,c=v.c}
  assert(r.attacks(match,1)[r.key(target.r,target.c)])
  local ok,event=r.apply(match,{type='attack',id=1,r=target.r,c=target.c})
  assert(ok,event)
  assert(not (event.attackerHpEnd==0 and event.defenderHpEnd==0))
  for _,roll in ipairs(event.rounds) do
    assert(roll.a>=1 and roll.a<=8 and roll.b>=1 and roll.b<=8)
    if roll.a==roll.b then assert(roll.who=='tie' and roll.damage==0);found.tie=true
    elseif roll.a>roll.b then assert(roll.who=='attacker' and roll.damage==r.classes[u.class].hit)
    else assert(roll.who=='defender' and roll.damage==r.classes[v.class].hit) end
  end
  if u.hp>0 then
    found.attacker=true
    assert(event.captured)
    eq(u.r,target.r);eq(u.c,target.c)
    eq(v.hp,0)
  else
    found.defender=true
    eq(v.r,target.r);eq(v.c,target.c)
    eq(u.r,from.r);eq(u.c,from.c)
  end
  assert(event.heal and event.heal.roll>=4 and event.heal.roll<=10)
end
assert(found.attacker and found.defender and found.tie)
local siegeSeen={winner=false,mutual=false}
for seed=1,1000 do
  local match=r.new(seed)
  for _,unit in ipairs(match.units) do if unit.id~=1 then unit.hp=0 end end
  local u=match.units[1];u.r,u.c=2,3;u.hp=1;match.turn=1
  match.forts[1].hp=7;match.forts[2].hp=20
  local ok,event=r.apply(match,{type='attack',id=1,r=1,c=3})
  assert(ok,event)
  for _,v in ipairs(event.rounds) do if v.who=='defender' then eq(v.damage,5) end end
  if u.hp==0 then
    assert(event.siege and #event.siege>0)
    for _,volley in ipairs(event.siege) do
      eq(volley.hit1,volley.a>=4 and 7 or 0)
      eq(volley.hit2,volley.b>=4 and 7 or 0)
    end
    siegeSeen.winner=true
    if match.winner==0 then siegeSeen.mutual=true end
  end
  if siegeSeen.winner and siegeSeen.mutual then break end
end
assert(siegeSeen.winner and siegeSeen.mutual)
local match=r.new(481)
local move
for key in pairs(r.moves(match,1)) do
  local row,col=r.fromkey(key);move={type='move',id=1,r=row,c=col};break
end
assert(move);assert(r.apply(match,move))
local restored,err=r.restore(r.serialize(match))
assert(restored,err)
eq(restored.rng,match.rng)
for i,u in ipairs(match.units) do eq(restored.units[i].hp,u.hp);eq(restored.units[i].r,u.r);eq(restored.units[i].c,u.c) end
assert(not r.replay(match.seed,{'M2_1_3'}))
print('PASS: geometry, 20 units, D8 fixed hits, unique victor, Chess captures, fortress, Final Siege, deterministic replay')
