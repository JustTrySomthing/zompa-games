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
local shields={soldier=2,assassin=3,ogre=5,barbarian=5,fortress=3,wizard=4,archer=3}
local powers={soldier=8,assassin=10,ogre=12,barbarian=11,fortress=8,wizard=10,archer=6}
local health={soldier=16,assassin=18,ogre=24,barbarian=25,fortress=30,wizard=18,archer=14}
for name,stats in pairs(r.classes) do
 eq(stats.shield,shields[name]);eq(stats.power,powers[name]);eq(stats.hp,health[name])
 assert(stats.power>=1 and stats.power<=12 and stats.shield>=1 and stats.shield<=12)
end
local rolls,bonuses={},{}
local equality=false
for seed=1,240 do
 local st=r.new(seed)
 local attacker,defender=st.units[8],st.units[23]
 attacker.r,attacker.c,attacker.hp=4,1,10
 defender.r,defender.c,defender.hp=4,2,10
 local action={type='attack',id=8,r=4,c=2}
 local ok,event=r.apply(st,action);assert(ok,event)
 rolls[event.roll]=true
 eq(st.turn,2);eq(st.moves,1)
 eq(attacker.r,4);eq(attacker.c,1)
 eq(event.landed,event.roll>event.shield)
 if event.landed then
  eq(defender.hp,0);eq(event.damage,10)
  bonuses[event.heal.roll]=true
  eq(attacker.hp,math.min(18,10+event.heal.roll))
 else
  eq(defender.hp,10);eq(attacker.hp,10);eq(event.heal,nil)
  if event.roll==event.shield then equality=true end
 end
end
assert(equality,'Shield ties must repel')
for i=1,12 do assert(rolls[i] and bonuses[i],'both dice must cover all twelve faces') end
local st=r.new(17)
local a=st.units[8];a.r,a.c=4,1
local b=st.units[23];b.r,b.c=4,2;b.hp=18
assert(r.apply(st,{type='attack',id=a.id,r=4,c=2}))
assert(b.hp==18 or b.hp==8)
assert(st.last.heal==nil and a.hp==18)
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
assert(saved:sub(1,4)=='v18|')
local restored,err=r.restore(saved);assert(restored,err)
eq(restored.previous.actor,2);eq(restored.previous.id,second.id)
for i,u in ipairs(clean.units) do
 eq(restored.units[i].hp,u.hp);eq(restored.units[i].r,u.r);eq(restored.units[i].c,u.c)
end
assert(not r.decode('M31_1_3'))
assert(not r.restore('v16|'..saved:sub(5)),'older stats must not affect new match replay')
assert(not r.restore('v5|123|'),'incompatible old-layout saved games must not load')
assert(not r.restore('v6|'..saved:sub(5)),'must not replay v0.5.0 saves under changed movement and combat rules')
assert(not r.restore('v7|'..saved:sub(5)),'must not replay old actions against the new starting formation')
assert(not r.restore('v8|'..saved:sub(5)),'old rules must not replay against the test movement')
assert(not r.restore('v11|'..saved:sub(5)),'old Archer layout cannot replay against corrected formation')
print('PASS: 56 playable fitted hexes, 30 mirrored units, 2 forts, 6 neighbors, D12 combat and v18 saves')

local starts,ties={0,0},0
for seed=1,1200 do
 local opening=r.initiative(seed)
 local final=opening.rounds[#opening.rounds]
 eq(opening.first,final[1]>final[2] and 1 or 2)
 assert(final[1]~=final[2])
 for i,roll in ipairs(opening.rounds) do
  assert(roll[1]>=1 and roll[1]<=12 and roll[2]>=1 and roll[2]<=12)
  if i<#opening.rounds then eq(roll[1],roll[2]);ties=ties+1 end
 end
 starts[opening.first]=starts[opening.first]+1
end
assert(starts[1]>500 and starts[2]>500 and ties>50)
local blueStart=r.new(123,2)
assert(r.apply(blueStart,r.actions(blueStart)[1]))
local blueRestored=assert(r.restore(r.serialize(blueStart)))
eq(blueRestored.first,2);eq(blueRestored.turn,1)
eq(assert(r.restore('v17|123|')).turn,1)

local siegeTies=0
for seed=1,64 do
 local field=r.new(seed)
 for _,unit in ipairs(field.units) do unit.hp=0 end
 field.forts[1].hp,field.forts[2].hp=9,30
 local ok,event=r.apply(field,{type='pass'})
 assert(ok and event.siege and event.winner==field.winner)
 local hp=event.siege.start
 assert(hp[1]==9 and hp[2]==30)
 for index,volley in ipairs(event.siege.volleys) do
  assert(volley.a>=1 and volley.a<=12 and volley.b>=1 and volley.b<=12)
  if volley.a==volley.b then
   siegeTies=siegeTies+1
   eq(volley.hit,0);eq(volley.hp[1],hp[1]);eq(volley.hp[2],hp[2])
  else
   local winner=volley.a>volley.b and 1 or 2
   eq(volley.hit,winner);eq(volley.hp[winner],hp[winner])
   eq(volley.hp[3-winner],math.max(0,hp[3-winner]-r.classes.fortress.power))
  end
  hp=volley.hp
  if index<#event.siege.volleys then assert(hp[1]>0 and hp[2]>0) end
 end
 assert(hp[field.winner]>0 and hp[3-field.winner]==0)
end
assert(siegeTies>0)

-- Killing the last troop with a Fortress leads into the siege immediately.
local endgame=r.new(1)
for _,unit in ipairs(endgame.units) do unit.hp=0 end
local attacker=endgame.forts[1]
attacker.armed=true
local target=endgame.units[17]
target.r,target.c,target.hp=8,1,2
for seed=1,20 do
 local trial=r.copy(endgame)
 trial.rng=seed
 local ok,event=r.apply(trial,{type='attack',id=attacker.id,r=target.r,c=target.c})
 assert(ok)
 if event.defeated then
  assert(event.siege and event.finish=='siege' and event.winner~=0)
  endgame=nil
  break
 end
end
assert(not endgame)
print('PASS: initiative ties reroll, both sides can open, and Final Siege resolves a single winner')
