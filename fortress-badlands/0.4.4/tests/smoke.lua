package.path='./?.lua;'..package.path
local r=require('rules')
local function eq(a,b)assert(a==b,tostring(a)..' ~= '..tostring(b))end
local s=r.new(123)
eq(r.ROWS,10);eq(r.COLS,7);eq(#s.units,28);eq(r.count(s,1),14);eq(r.count(s,2),14)
local n=0
for row=0,9 do for col=0,6 do
 if r.playable(row,col)then n=n+1 end
end end
eq(n,58)
for col=0,6 do
 eq(r.playable(0,col),col>=2 and col<=4)
 eq(r.playable(1,col),col>=1 and col<=5)
 eq(r.playable(9,col),col>=2 and col<=4)
 eq(r.playable(8,col),col>=1 and col<=5)
end
local counts={soldier=0,wizard=0,assassin=0,barbarian=0,ogre=0}
for _,u in ipairs(s.units)do
 assert(r.playable(u.r,u.c))
 if u.owner==1 then counts[u.class]=counts[u.class]+1 end
 assert(r.occupied(s,u.r,u.c).ref==u)
end
for cl,n in pairs({soldier=4,wizard=2,assassin=3,barbarian=3,ogre=2})do eq(counts[cl],n) end
for i=1,14 do
 local a,b=s.units[i],s.units[i+14]
 eq(b.r,9-a.r);eq(b.c,a.c);eq(b.class,a.class)
end
eq(s.forts[1].r,9);eq(s.forts[2].r,0)
assert(r.moves(s,8)[r.key(6,0)])
assert(not r.playable(9,0));assert(not r.playable(8,0))
-- No movement through the removed squares, even if a direct geometric distance looks short.
assert(not r.moves(s,1)[r.key(9,1)])
local hits={attacker=false,defender=false,tie=false}
for seed=1,240 do
 local st=r.new(seed)
 for _,u in ipairs(st.units)do if u.id~=8 and u.id~=22 then u.hp=0 end end
 local a,b=st.units[8],st.units[22]
 a.r,a.c,a.hp=5,2,14;b.r,b.c,b.hp=4,2,14;st.turn=1
 local ok,e=r.apply(st,{type='attack',id=8,r=4,c=2});assert(ok,e)
 assert(not (a.hp<=0 and b.hp<=0))
 assert(e.heal and e.heal.roll>=1 and e.heal.roll<=8,'heal roll must be D8 1–8')
 assert(e.heal.actual>=0 and e.heal.actual<=e.heal.roll,'heal cannot exceed max HP')
 if a.hp>0 then hits.attacker=true;eq(a.r,4);eq(a.c,2)else hits.defender=true;eq(b.r,4);eq(b.c,2)end
 for _,roll in ipairs(e.rounds)do
  if roll.who=='tie'then hits.tie=true;eq(roll.damage,0) end
  assert(roll.a>=1 and roll.a<=8 and roll.b>=1 and roll.b<=8)
 end
end
assert(hits.attacker and hits.defender and hits.tie)
-- Fortress/Final Siege retained.
for seed=1,100 do
 local st=r.new(seed)
 for _,u in ipairs(st.units)do if u.id~=8 then u.hp=0 end end
 local a=st.units[8];a.r,a.c,a.hp=1,3,1;st.turn=1
 assert(r.attacks(st,8)[r.key(0,3)])
 assert(r.apply(st,{type='attack',id=8,r=0,c=3}))
 if a.hp==0 then assert(st.winner~=nil and st.finish=='siege' or st.finish=='mutual') end
end
-- Healing is a replay-deterministic D8 result for both kingdoms.
local observed={}
for seed=1,450 do
  local match=r.new(seed*23)
  for _,u in ipairs(match.units) do if u.id~=8 and u.id~=22 then u.hp=0 end end
  local a,b=match.units[8],match.units[22]
  a.r,a.c,a.hp=5,2,14
  b.r,b.c,b.hp=4,2,14
  match.turn=1
  local ok,e=r.apply(match,{type='attack',id=8,r=4,c=2})
  assert(ok,e)
  assert(e.heal and e.heal.roll>=1 and e.heal.roll<=8)
  observed[e.heal.roll]=true
  local restored,err=r.restore(r.serialize(match))
  assert(restored,err)
  assert(restored.rng==match.rng,'healing roll alters replay RNG')
end
for value=1,8 do assert(observed[value],'D8 reward lacks outcome '..value) end
local clean=r.new(4217)
local acts=r.actions(clean);assert(#acts>0)
assert(r.apply(clean,acts[1]))
local restored,err=r.restore(r.serialize(clean));assert(restored,err)
for i,u in ipairs(clean.units) do eq(restored.units[i].hp,u.hp);eq(restored.units[i].r,u.r);eq(restored.units[i].c,u.c) end
assert(not r.decode('M29_1_3'))
print('PASS: exactly 58 playable cells, 12 absent corners, 28 mirrored troops, D8/HP/combat/replay/fortress')
