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

-- Soldier march follows one of the six straight radial lines only.
local s=clean()
local soldier=s.units[1]
soldier.hp=22;soldier.r=5;soldier.c=2
assert(rules.moves(s,soldier.id)[key(5,4)],'Soldier cannot march straight 2')
assert(not rules.moves(s,soldier.id)[key(6,4)],
  'Soldier incorrectly bends midway through a two-hex march')
local path=rules.route(s,soldier.id,5,4)
assert(path and #path==3 and path[2].r==5 and path[2].c==3,
  'March route must include the intermediate straight hex')
local blocker=s.units[2]
blocker.hp=22;blocker.r=5;blocker.c=3
assert(not rules.moves(s,soldier.id)[key(5,4)],
  'Soldier cannot march past a friendly blocker')
blocker.hp=0
local foe=s.units[16]
foe.hp=22;foe.r=5;foe.c=4
assert(rules.attacks(s,soldier.id)[key(5,4)],
  'Soldier should be able to attack straight down the march line')
blocker.hp=22
assert(not rules.attacks(s,soldier.id)[key(5,4)],
  'Soldier cannot attack beyond a blocking first hex')

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
print('PASS: Soldier straight-line march and blockers; Wizard two-hex teleport over units; class HIT changes and replay')
