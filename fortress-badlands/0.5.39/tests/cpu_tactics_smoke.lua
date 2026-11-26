local rules=require('rules')
local choose=require('cpu')
local state=rules.new(1,2)
for _,unit in ipairs(state.units) do unit.hp=0 end
local wizard=state.units[18]
local left,right,front=state.units[3],state.units[6],state.units[12]
local function put(unit,hp,r,c)
  unit.hp,unit.r,unit.c=hp,r,c
end
local function pick()
  local rng=state.rng
  local action=choose(state,function() return 0 end)
  assert(state.rng==rng and state.moves==0,'CPU must not preview the actual dice rolls')
  return assert(action)
end

put(wizard,2,5,2)
put(left,18,6,1)
put(right,18,6,3)
put(front,16,6,2)
local retreat=pick()
assert(retreat.type=='move' and retreat.id==wizard.id,'wounded Wizard should retreat')
for _,enemy in ipairs({left,right,front}) do
  assert(rules.inAttackRange(enemy,wizard),'fixture must threaten the Wizard')
  assert(not rules.inAttackRange(enemy,retreat),'retreat must clear the enemies’ strike ranges')
end
assert(rules.apply(rules.copy(state),retreat),'retreat must respect Wizard movement rules')

-- One opponent can be finished, and any repositioning leaves nearby ranged threats.
-- The wounded Wizard can gamble on putting the Archer out and healing from the kill.
left=state.units[4]
state.units[3].hp=0
put(left,2,5,0)
put(right,18,5,3)
wizard.hp=5
local attack=pick()
assert(attack.type=='attack' and attack.id==wizard.id and attack.r==left.r and attack.c==left.c,
  'CPU should take an available finishing strike when the reward can justify exposure')
assert(rules.apply(rules.copy(state),attack),'attack must respect Wizard strike range')
print('PASS: wounded CPU retreats from overlapping threats and weighs a finishing attack against its healing reward')

-- A tempting attack across the board must not distract the CPU from its Fortress.
state=rules.new(123,2)
for _,unit in ipairs(state.units) do unit.hp=0 end
put(state.units[18],18,3,2)
put(state.units[22],24,9,0)
put(state.units[3],18,1,0)
put(state.units[4],14,1,1)
put(state.units[12],16,1,2)
local defense=pick()
assert(defense.type=='attack' and defense.id==18 and defense.r==1,
  'the CPU should use a defender when three enemies threaten its Fortress')
state.units[18].r=4
defense=pick()
assert(defense.type=='move' and defense.id==18,
  'the CPU should reposition a defender before committing elsewhere')
assert(rules.inAttackRange({class='wizard',r=defense.r,c=defense.c},state.units[12]),
  'the defender should cover a troop threatening the Fortress')
state.units[18].r=3
state.units[4].hp,state.units[12].hp=0,0
state.forts[2].armed=true
state.last={type='attack',actor=1,defenderClass='fortress'}
defense=pick()
assert(defense.type=='attack' and defense.r==1 and defense.c==0,
  'the CPU must respond to a direct Fortress attack even from a single enemy')
print('PASS: CPU intercepts coordinated threats, repositions defenders, and responds after a Fortress attack')
