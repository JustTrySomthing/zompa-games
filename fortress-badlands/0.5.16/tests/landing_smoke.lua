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
local function legalRange(piece,finish)
  local moves=r.moves(board,piece.id)
  assert(moves[r.key(4,finish)]==4,'Archer can move four hexes down a clear line')
  assert(#r.route(board,piece.id,4,finish)==5,'Archer follows each hex in its path')
end
assert(not r.moves(board,archer.id)[r.key(4,1)],'Ally blocks landing')
assert(not r.attacks(board,archer.id)[r.key(4,2)],'Ally blocks an attack behind it')
assert(not r.route(board,archer.id,4,4),'Ally blocks movement beyond it')
ally.hp=0
assert(r.moves(board,archer.id)[r.key(4,1)])
assert(r.attacks(board,archer.id)[r.key(4,2)],'First enemy may be attacked')
assert(not r.route(board,archer.id,4,3),'Enemy blocks movement beyond it')
local farther=board.units[17]
farther.hp,farther.r,farther.c=32,4,4
assert(not r.attacks(board,archer.id)[r.key(4,4)],'Enemy blocks attacks beyond it')
enemy.hp,farther.hp=0,0
legalRange(archer,4)
assert(not r.route(board,archer.id,4,5) and not r.route(board,archer.id,5,3))
farther.hp=32
assert(r.attacks(board,archer.id)[r.key(4,4)],'Archer can attack at range four')
assert(not next(r.jumpOver(board,archer.id,4,4)),'Archer shows no jump outlines')
board.forts[2].r,board.forts[2].c=4,3
assert(r.attacks(board,archer.id)[r.key(4,3)] and not r.route(board,archer.id,4,4))
local blue=board.units[20]
blue.hp,blue.r,blue.c=20,6,6
ally.hp,ally.r,ally.c=32,6,4
board.turn=2
assert(r.attacks(board,blue.id)[r.key(6,4)] and not r.route(board,blue.id,6,2))
ally.hp=0
assert(r.apply(board,{type='move',id=blue.id,r=6,c=2}))
print('PASS: either Archer moves up to four hexes, cannot turn, and stops at the first piece')

-- The old opening skipped past a troop. Keep that history readable while
-- enforcing the blocked range on all new moves and after a second reload.
local fresh=r.new(123)
assert(not r.route(fresh,4,6,1))
local migrated,err=r.restore('v14|123|M4_6_1')
assert(migrated,err)
assert(migrated.units[4].r==6 and migrated.units[4].c==1 and not migrated.replayingV14)
local reply
for _,action in ipairs(r.actions(migrated)) do
  if action.type=='move' then reply=action;break end
end
assert(r.apply(migrated,reply))
local resumed,replayError=r.restore(r.serialize(migrated))
assert(resumed,replayError)
assert(resumed.turn==1 and resumed.moves==2 and resumed.v14Turns==1)
print('PASS: prior Archer jumps survive a save migration and a subsequent move')
