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

local board=r.new(123)
for _,unit in ipairs(board.units) do unit.hp=0 end
local archer,ally,enemy=board.units[4],board.units[1],board.units[16]
archer.hp=16;archer.r,archer.c=4,0
ally.hp=24;ally.r,ally.c=4,1
enemy.hp=24;enemy.r,enemy.c=4,2
local moves=r.moves(board,archer.id)
assert(moves[r.key(4,4)]==4, 'Archer must cross friendly and enemy troops')
local crossed=r.jumpOver(board,archer.id,4,4)
assert(crossed[r.key(4,1)] and crossed[r.key(4,2)] and not crossed[r.key(4,3)])
assert(not r.jumpOver(board,archer.id,4,2)[r.key(4,2)],'Landing target must not have a jump outline')
assert(not moves[r.key(4,1)], 'Archer cannot finish on an ally')
assert(not moves[r.key(4,5)] and not moves[r.key(5,3)], 'Archer cannot exceed four hexes or turn')
assert(r.attacks(board,archer.id)[r.key(4,2)], 'Archer can attack an enemy on its line')
enemy.c=4
assert(r.attacks(board,archer.id)[r.key(4,4)], 'Archer can attack up to four hexes away')
assert(#r.route(board,archer.id,4,4)==2,'Jump route skips intermediate landing')
board.forts[2].r,board.forts[2].c=4,3
assert(r.attacks(board,archer.id)[r.key(4,3)] and not r.route(board,archer.id,4,4))
local blue=board.units[20]
blue.hp=16;blue.r,blue.c=6,6
board.turn=2
assert(r.moves(board,blue.id)[r.key(6,2)]==4)
assert(r.decode('M20_6_2').id==blue.id)
assert(r.apply(board,{type='move',id=blue.id,r=6,c=2}))
print('PASS: both Archers can jump along four-hex straight routes')
