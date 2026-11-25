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

-- Forward follows the owner's side, using either hex in the next row.
for owner=1,2 do
 local state=clean()
 state.turn=owner
 local soldier=state.units[owner==1 and 13 or 29]
 soldier.hp=22;soldier.r=5;soldier.c=2
 local forwardRow=owner==1 and 4 or 6
 local forward={}
 local moves=rules.moves(state,soldier.id)
 for _,target in ipairs(rules.neighbors(5,2)) do
  local destination=key(target.r,target.c)
  if target.r==forwardRow then
   assert(moves[destination]==1 and #rules.route(state,soldier.id,target.r,target.c)==2)
   forward[#forward+1]=target
  else
   assert(not moves[destination],'Soldier can neither retreat nor move sideways')
  end
 end
 assert(#forward==2 and not moves[key(owner==1 and 3 or 7,2)])
 local ally=state.units[owner==1 and 1 or 17]
 ally.hp=24;ally.r,ally.c=forward[1].r,forward[1].c
 assert(not rules.route(state,soldier.id,ally.r,ally.c),'A friendly piece blocks the Soldier')
 local enemy=state.units[owner==1 and 17 or 1]
 enemy.hp=24;enemy.r,enemy.c=forward[2].r,forward[2].c
 assert(rules.attacks(state,soldier.id)[key(enemy.r,enemy.c)],'The forward hex can be attacked')
 assert(not rules.moves(state,soldier.id)[key(enemy.r,enemy.c)])
 enemy.r,enemy.c=5,3
 assert(not rules.attacks(state,soldier.id)[key(5,3)],'Soldier cannot attack sideways')
 enemy.r,enemy.c=owner==1 and 6 or 4,2
 assert(not rules.attacks(state,soldier.id)[key(enemy.r,enemy.c)],'Soldier cannot attack behind itself')
 assert(not rules.apply(state,{type='pass'}),'A side with a legal action cannot pass')
end

local s=clean()
local ogre=s.units[4]
ogre.hp=28;ogre.r=5;ogre.c=2
local count=0
for _ in pairs(rules.moves(s,ogre.id)) do count=count+1 end
assert(count==6,'Ogres retain all six directions')

s=clean()
local red,blue=s.units[13],s.units[29]
red.hp=22;red.r,red.c=0,0
blue.hp=22;blue.r,blue.c=10,0
assert(rules.mustPass(s) and rules.actions(s)[1].type=='pass')
assert(rules.apply(s,{type='pass'}))
assert(s.winner==nil and rules.mustPass(s))
assert(rules.apply(s,{type='pass'}))
assert(s.winner==0 and s.finish=='stalemate','Two forced passes end the match')

assert(rules.classes.wizard.hp==24 and rules.classes.assassin.hp==18)
assert(rules.classes.barbarian.hp==24 and rules.FORT_HP==50)

-- Wizard can teleport OVER friends or enemies but not land on an ally.
s=clean()
local wizard=s.units[3] -- first Wizard in the approved back-rank formation
assert(wizard.class=='wizard')
wizard.hp=16;wizard.r=5;wizard.c=2
local blocker=s.units[1];blocker.hp=22;blocker.r=5;blocker.c=3
assert(rules.moves(s,wizard.id)[key(5,4)],
  'Wizard cannot teleport over an allied piece to an open target')
local teleportRoute=rules.route(s,wizard.id,5,4)
assert(teleportRoute and #teleportRoute==2,
  'Teleport route must skip intermediate occupied hex')
assert(not rules.moves(s,wizard.id)[key(5,3)],
  'Wizard cannot land on an ally')
assert(not rules.moves(s,wizard.id)[key(5,5)],
  'Wizard teleport may not exceed two hexes')
local foe=s.units[17];foe.hp=22;foe.r=5;foe.c=4
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
print('PASS: Forward-only Soldiers, mirrored attacks and forced passes; Wizard two-hex teleport over units; class HIT changes and replay')
