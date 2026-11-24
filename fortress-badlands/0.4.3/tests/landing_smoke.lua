package.path='./?.lua;'..package.path
local r=require('rules')
local s=r.new(123)
for _,u in ipairs(s.units)do if u.id~=8 and u.id~=22 then u.hp=0 end end
local a,b=s.units[8],s.units[22]
a.r,a.c,a.hp=7,2,14
b.r,b.c,b.hp=4,2,14
s.turn=1
assert(r.attacks(s,8)[r.key(4,2)],'Assassin with move=3 should attack by landing 3 squares away')
local route=r.route(s,8,4,2);assert(route and #route==4)
-- a blocking friendly soldier prevents occupation and jumping
s.units[1].hp=22;s.units[1].r,s.units[1].c=6,2
assert(not r.playable(9,1))
local empty,bad=r.moves(s,8),r.attacks(s,8)
assert(not empty[r.key(9,1)])
-- A diagonal route may still exist around one blocking soldier.
assert(bad[r.key(4,2)]~=nil)
s.units[1].hp=0
local ok,event=r.apply(s,{type='attack',id=8,r=4,c=2});assert(ok,event)
if a.hp>0 then assert(a.r==4 and a.c==2 and event.captured) end
print('PASS: move-distance captures, blocked phantom corners, deterministic combat')
