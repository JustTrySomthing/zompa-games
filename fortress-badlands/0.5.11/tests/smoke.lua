package.path='./?.lua;'..package.path
local r=require('rules')
local function eq(a,b)assert(a==b,tostring(a)..' ~= '..tostring(b))end
local s=r.new(123)
eq(r.ROWS,11);eq(r.COLS,7)
eq(#s.units,30);eq(r.count(s,1),15);eq(r.count(s,2),15)
local shape={3,4,5,6,7,6,7,6,5,4,3}
local cells=0
for row=0,10 do
 eq(r.rowWidths[row+1],shape[row+1])
 for col=0,6 do
  eq(r.playable(row,col),col<shape[row+1])
  if r.playable(row,col) then cells=cells+1 end
 end
end
eq(cells,56)
local counts={archer=0,soldier=0,wizard=0,assassin=0,barbarian=0,ogre=0}
local occupied={}
for _,u in ipairs(s.units) do
 assert(r.playable(u.r,u.c))
 if u.owner==1 then counts[u.class]=counts[u.class]+1 end
 local id=r.key(u.r,u.c)
 assert(not occupied[u.owner..':'..id],'duplicate starting hex')
 occupied[u.owner..':'..id]=true
 assert(r.occupied(s,u.r,u.c).ref==u)
end
for class,n in pairs({archer=2,soldier=4,wizard=2,assassin=2,barbarian=3,ogre=2}) do
 eq(counts[class],n)
end
for i=1,15 do
 local a,b=s.units[i],s.units[i+15]
 eq(b.r,10-a.r);eq(b.c,a.c);eq(b.class,a.class)
end
eq(s.forts[1].r,10);eq(s.forts[1].c,1)
eq(s.forts[2].r,0);eq(s.forts[2].c,1)
eq(r.occupied(s,10,1).kind,'fort')
eq(r.occupied(s,0,1).kind,'fort')
for _,rear in ipairs({0,10}) do
 local front=rear==0 and 3 or 7
 for _,col in ipairs({0,2}) do eq(r.occupied(s,rear,col).ref.class,'barbarian') end
 for col=1,4 do eq(r.occupied(s,front,col).ref.class,'soldier') end
 eq(r.occupied(s,front,0),nil);eq(r.occupied(s,front,5),nil)
 local second=rear==0 and 1 or 9
 for col=1,2 do eq(r.occupied(s,second,col).ref.class,'archer') end
end
-- Actual adjacent hexes, not the old 8-square crossing moves.
for row=0,10 do for col=0,shape[row+1]-1 do
 local neighbors=r.neighbors(row,col)
 assert(#neighbors>=2 and #neighbors<=6)
 for _,p in ipairs(neighbors) do
  assert(r.playable(p.r,p.c))
  eq(r.distance({r=row,c=col},p),1)
  local reciprocal=false
  for _,q in ipairs(r.neighbors(p.r,p.c)) do
   if q.r==row and q.c==col then reciprocal=true end
  end
  assert(reciprocal,'hex neighbors must be symmetric')
 end
end end
local battleSeen={attacker=false,defender=false,tie=false}
for seed=1,240 do
 local st=r.new(seed)
 for _,u in ipairs(st.units) do if u.id~=8 and u.id~=23 then u.hp=0 end end
 local a,b=st.units[8],st.units[23]
 assert(a.class=='assassin' and b.class=='assassin')
 a.r,a.c,a.hp=5,2,14
 b.r,b.c,b.hp=4,2,14
 st.turn=1
 local ok,e=r.apply(st,{type='attack',id=8,r=4,c=2});assert(ok,e)
 assert(not (a.hp<=0 and b.hp<=0))
 assert(e.heal and e.heal.roll>=1 and e.heal.roll<=8)
 assert(e.heal.actual>=0 and e.heal.actual<=e.heal.roll)
 if a.hp>0 then battleSeen.attacker=true;eq(a.r,4);eq(a.c,2)
 else battleSeen.defender=true;eq(b.r,4);eq(b.c,2) end
 for _,roll in ipairs(e.rounds) do
  if roll.who=='tie' then battleSeen.tie=true;eq(roll.damage,0) end
  assert(roll.a>=1 and roll.a<=8 and roll.b>=1 and roll.b<=8)
 end
end
assert(battleSeen.attacker and battleSeen.defender and battleSeen.tie)
-- Fortress siege and immediate attack use exactly the original battle D8.
for seed=1,100 do
 local st=r.new(seed)
 for _,u in ipairs(st.units) do if u.id~=8 then u.hp=0 end end
 local a=st.units[8];a.r,a.c,a.hp=1,1,1;st.turn=1
 assert(r.attacks(st,8)[r.key(0,1)],'fortress not reachable from adjacent top row')
 local ok,e=r.apply(st,{type='attack',id=8,r=0,c=1});assert(ok,e)
 if a.hp<=0 then assert(st.winner~=nil and (st.finish=='siege' or st.finish=='mutual')) end
end
-- D8 healing remains deterministic and the current save has an exact replay.
local seen={}
for seed=1,450 do
 local function prepare()
  local st=r.new(seed*23)
  for _,unit in ipairs(st.units) do if unit.id~=8 and unit.id~=23 then unit.hp=0 end end
  local a,b=st.units[8],st.units[23]
  a.r,a.c,a.hp=5,2,14;b.r,b.c,b.hp=4,2,14
  st.turn=1
  return st
 end
 local a,b=prepare(),prepare()
 local ok,e=r.apply(a,{type='attack',id=8,r=4,c=2});assert(ok,e)
 local ok2,e2=r.apply(b,{type='attack',id=8,r=4,c=2});assert(ok2,e2)
 seen[e.heal.roll]=true
 eq(e.heal.roll,e2.heal.roll);eq(a.rng,b.rng)
end
for i=1,8 do assert(seen[i],'missing D8 healing roll '..i) end
local clean=r.new(4217)
local acts=r.actions(clean);assert(#acts>0)
assert(r.apply(clean,acts[1]))
local second=r.actions(clean)[1]
assert(r.apply(clean,second))
local third=r.actions(clean)[1]
assert(r.apply(clean,third))
eq(clean.last.actor,1)
eq(clean.previous.actor,2)
eq(clean.previous.id,second.id)
local copy=r.copy(clean)
eq(copy.previous.id,second.id)
assert(copy.previous~=clean.previous,'CPU history should copy independently')
local saved=r.serialize(clean)
assert(saved:sub(1,4)=='v13|')
local restored,err=r.restore(saved);assert(restored,err)
eq(restored.previous.actor,2);eq(restored.previous.id,second.id)
for i,u in ipairs(clean.units) do
 eq(restored.units[i].hp,u.hp);eq(restored.units[i].r,u.r);eq(restored.units[i].c,u.c)
end
assert(not r.decode('M31_1_3'))
assert(not r.restore('v5|123|'),'incompatible old-layout saved games must not load')
assert(not r.restore('v6|'..saved:sub(5)),'must not replay v0.5.0 saves under changed movement and combat rules')
assert(not r.restore('v7|'..saved:sub(5)),'must not replay old actions against the new starting formation')
assert(not r.restore('v8|'..saved:sub(5)),'old rules must not replay against the test movement')
assert(not r.restore('v11|'..saved:sub(5)),'old Archer layout cannot replay against corrected formation')
print('PASS: 56 playable fitted hexes, 30 mirrored units, 2 forts, 6 neighbors, D8 combat and v13 saves')
