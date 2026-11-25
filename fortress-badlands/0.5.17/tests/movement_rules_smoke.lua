package.path='./?.lua;'..package.path
local rules=require('rules')
local function key(r,c) return rules.key(r,c) end
local function clean()
 local s=rules.new(33071)
 for _,u in ipairs(s.units) do u.hp=0 end
 s.turn=1
 return s
end

local s=clean()
local ogre=s.units[7]
ogre.hp=28;ogre.r=5;ogre.c=2
local count=0
for _ in pairs(rules.moves(s,ogre.id)) do count=count+1 end
assert(count==6,'Ogres retain all six directions')

s=clean()
local red,blue=s.units[13],s.units[28]
red.hp=0
blue.hp=0
assert(rules.mustPass(s) and rules.actions(s)[1].type=='pass')
assert(rules.apply(s,{type='pass'}))
assert(s.winner==nil and rules.mustPass(s))
assert(rules.apply(s,{type='pass'}))
assert(s.winner==0 and s.finish=='stalemate','Two forced passes end the match')

assert(rules.classes.wizard.hp==48 and rules.FORT_HP==60)

-- Wizard can teleport OVER friends or enemies but not land on an ally.
s=clean()
local wizard=s.units[3] -- first Wizard in the approved back-rank formation
assert(wizard.class=='wizard')
wizard.hp=16;wizard.r=5;wizard.c=2
local blocker=s.units[1];blocker.hp=22;blocker.r=5;blocker.c=3
assert(rules.jumpOver(s,wizard.id,5,4)[key(5,3)],'Teleport cue must include the crossed troop')
assert(rules.moves(s,wizard.id)[key(5,4)],
  'Wizard cannot teleport over an allied piece to an open target')
local teleportRoute=rules.route(s,wizard.id,5,4)
assert(teleportRoute and #teleportRoute==2,
  'Teleport route must skip intermediate occupied hex')
assert(not rules.moves(s,wizard.id)[key(5,3)],
  'Wizard cannot land on an ally')
assert(not rules.moves(s,wizard.id)[key(5,5)],
  'Wizard teleport may not exceed two hexes')
local foe=s.units[16];foe.hp=22;foe.r=5;foe.c=4
assert(not rules.attacks(s,wizard.id)[key(5,4)],'Wizard must attack adjacent hexes')
assert(not rules.moves(s,wizard.id)[key(5,4)],
  'An occupied hex cannot be a move destination')
assert(not rules.route(s,wizard.id,5,4))
-- A legal opening-board teleport replays from the original formation.
local opening=rules.new(33071)
assert(rules.moves(opening,3)[key(7,0)],
  'Opening Wizard should teleport over its Archer to empty flank')
local okay,ev=rules.apply(opening,{type='move',id=3,r=7,c=0})
assert(okay,ev)
local restored,err=rules.restore(rules.serialize(opening))
assert(restored,err)
assert(restored.units[3].r==7 and restored.units[3].c==0,
  'teleport must reproduce exactly in local/online replay')
print('PASS: Forward-only Soldiers, mirrored attacks and forced passes; Wizard two-hex teleport over units; class rules and replay')
