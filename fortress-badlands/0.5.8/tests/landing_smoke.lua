package.path='./?.lua;'..package.path
local r=require('rules')
local s=r.new(123)
for _,u in ipairs(s.units) do u.hp=0 end
local a,b=s.units[8],s.units[23]
assert(a.class=='assassin' and b.class=='assassin')
a.r,a.c,a.hp=4,0,14
s.turn=1
local route=r.route(s,a.id,4,6)
assert(route and #route==7,'Assassin can travel a clear line past the former three-hex limit')
for i,p in ipairs(route) do assert(p.r==4 and p.c==i-1,'route bent') end
assert(not r.moves(s,a.id)[r.key(5,4)],'Assassin cannot turn a corner')
local diagonal=r.route(s,a.id,1,0)
assert(diagonal and #diagonal==4,'Assassin can follow a straight line across staggered rows')
local blocker=s.units[1]
blocker.hp=19;blocker.r,blocker.c=4,2
assert(not r.route(s,a.id,4,2) and not r.route(s,a.id,4,6),'Ally must stop the ray')
blocker.hp=0
b.r,b.c,b.hp=4,3,14
assert(r.attacks(s,a.id)[r.key(4,3)],'First enemy is a legal landing attack')
assert(not r.route(s,a.id,4,6),'Assassin cannot pass through the first enemy')
s.turn=2
assert(not r.moves(s,a.id)[r.key(4,1)],'Off-turn moves remain illegal')
local threats=r.threatenedHexes(s,a.id)
assert(threats[r.key(4,3)] and not threats[r.key(4,6)] and not threats[r.key(5,4)])
s.turn=1
b.c=6
local ok,event=r.apply(s,{type='attack',id=a.id,r=4,c=6})
assert(ok,event)
if a.hp>0 then assert(a.r==4 and a.c==6 and event.captured) end
local across=r.new(123)
for _,unit in ipairs(across.units) do unit.hp=0 end
local assassin=across.units[8]
assassin.hp=14;assassin.r,assassin.c=1,1
assert(r.attacks(across,assassin.id)[r.key(0,1)],'Enemy Fortress is a legal first target')
assert(not r.route(across,assassin.id,10,4),'Missing edge hex cannot alias a valid route')
print('PASS: six-direction straight routes, long attacks, first-occupant blocking and CPU threat lookup')
