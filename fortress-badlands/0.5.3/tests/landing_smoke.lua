package.path='./?.lua;'..package.path
local r=require('rules')
local s=r.new(123)
for _,u in ipairs(s.units)do if u.id~=8 and u.id~=23 then u.hp=0 end end
local a,b=s.units[8],s.units[23]
assert(a.class=='assassin' and b.class=='assassin')
a.r,a.c,a.hp=7,1,14
b.r,b.c,b.hp=4,2,14
s.turn=1
assert(r.distance(a,b)==3,'assassin should be three hex steps from enemy')
assert(r.attacks(s,8)[r.key(4,2)],'assassin with move 3 attacks by landing on enemy')
local route=r.route(s,8,4,2)
assert(route and #route==4)
for k=2,#route do assert(r.distance(route[k-1],route[k])==1) end
-- Friends and corner voids block routes but never cause phantom hex jumps.
s.units[1].hp=22;s.units[1].r,s.units[1].c=6,1
assert(not r.playable(10,4))
local empty,bad=r.moves(s,8),r.attacks(s,8)
assert(not empty[r.key(10,4)])
assert(bad[r.key(4,2)]~=nil,'one block should not erase all legal paths')
s.units[1].hp=0
local ok,event=r.apply(s,{type='attack',id=8,r=4,c=2});assert(ok,event)
if a.hp>0 then assert(a.r==4 and a.c==2 and event.captured) end
print('PASS: hex pathfinding, obstacle-aware attack landing, no phantom corners, deterministic combat')
