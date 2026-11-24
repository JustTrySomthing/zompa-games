package.path='./?.lua;'..package.path
local rules=require('rules')
local function key(r,c) return rules.key(r,c) end
local function clean()
 local s=rules.new(33071)
 for _,u in ipairs(s.units) do u.hp=0 end
 s.turn=1
 return s
end
assert(rules.classes.soldier.hit==4,'Soldier HIT must be 4')
assert(rules.classes.ogre.hit==7,'Ogre HIT must be 7')
assert(rules.classes.wizard.move==2,'Wizard TELEPORT must reach two hexes')

-- Soldiers and Ogres use the same six adjacent hexes.
local s=clean()
local soldier=s.units[13]
local ogre=s.units[4]
assert(soldier.class=='soldier' and ogre.class=='ogre')
soldier.hp=22;soldier.r=5;soldier.c=2
local neighbors=rules.neighbors(soldier.r,soldier.c)
assert(#neighbors==6)
local moves=rules.moves(s,soldier.id)
for _,target in ipairs(neighbors) do
 assert(moves[key(target.r,target.c)]==1,'Soldier cannot step to an adjacent hex')
 assert(#rules.route(s,soldier.id,target.r,target.c)==2)
end
for _,distance in pairs(moves) do assert(distance==1) end
assert(not moves[key(5,4)],'Soldier cannot move two hexes')
soldier.hp=0
ogre.hp=28;ogre.r=5;ogre.c=2
local ogreMoves=rules.moves(s,ogre.id)
for destination,distance in pairs(moves) do assert(ogreMoves[destination]==distance) end
for destination,distance in pairs(ogreMoves) do assert(moves[destination]==distance) end
ogre.hp=0
soldier.hp=22
local blocker=s.units[2]
blocker.hp=19;blocker.r=5;blocker.c=3
assert(not rules.moves(s,soldier.id)[key(5,3)],'Soldier cannot land on a friendly piece')
local foe=s.units[16]
foe.hp=19;foe.r=5;foe.c=4
assert(not rules.attacks(s,soldier.id)[key(5,4)],'Soldier cannot attack two hexes away')
blocker.hp=0
foe.c=3
assert(rules.attacks(s,soldier.id)[key(5,3)],'Soldier can attack an adjacent enemy')
assert(not rules.moves(s,soldier.id)[key(5,3)],'Enemy destination requires an attack')

-- Wizard can teleport OVER friends or enemies but not land on an ally.
s=clean()
local wizard=s.units[3] -- first Wizard in the approved back-rank formation
assert(wizard.class=='wizard')
wizard.hp=16;wizard.r=5;wizard.c=2
blocker=s.units[1];blocker.hp=22;blocker.r=5;blocker.c=3
assert(rules.moves(s,wizard.id)[key(5,4)],
  'Wizard cannot teleport over an allied piece to an open target')
local teleportRoute=rules.route(s,wizard.id,5,4)
assert(teleportRoute and #teleportRoute==2,
  'Teleport route must skip intermediate occupied hex')
assert(not rules.moves(s,wizard.id)[key(5,3)],
  'Wizard cannot land on an ally')
assert(not rules.moves(s,wizard.id)[key(5,5)],
  'Wizard teleport may not exceed two hexes')
foe=s.units[16];foe.hp=22;foe.r=5;foe.c=4
assert(rules.attacks(s,wizard.id)[key(5,4)],
  'Wizard must be able to teleport directly into combat')
assert(not rules.moves(s,wizard.id)[key(5,4)],
  'An enemy-occupied destination is an attack, not a move')
assert(rules.route(s,wizard.id,5,4) and #rules.route(s,wizard.id,5,4)==2)
-- A legal opening-board teleport replays from the original formation.
local opening=rules.new(33071)
assert(rules.moves(opening,3)[key(7,0)],
  'Opening Wizard should teleport over its Ogre to empty flank')
local okay,ev=rules.apply(opening,{type='move',id=3,r=7,c=0})
assert(okay,ev)
local restored,err=rules.restore(rules.serialize(opening))
assert(restored,err)
assert(restored.units[3].r==7 and restored.units[3].c==0,
  'teleport must reproduce exactly in local/online replay')
print('PASS: Soldier single-hex movement and adjacent attacks; Wizard two-hex teleport over units; class HIT changes and replay')
