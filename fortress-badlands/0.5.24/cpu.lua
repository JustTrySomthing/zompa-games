local rules=require('rules')

local function hitChance(piece)
  return (rules.DIE-rules.classes[piece.class].shield)/rules.DIE
end

local function healthBonus(piece)
  local missing=rules.classes[piece.class].hp-piece.hp
  local total=0
  for roll=1,rules.DIE do total=total+math.min(roll,missing) end
  return total/rules.DIE
end

-- The opponent gets one reply. Extra attackers matter because they can still
-- threaten this hex after a kill, but they cannot all hit in the same turn.
local function danger(piece,spot,hp,enemies,removed,armedFort)
  local worst,backup=0,0
  for _,enemy in ipairs(enemies) do
    local attacker=enemy==armedFort and {class='fortress',owner=enemy.owner,r=enemy.r,c=enemy.c,armed=true} or enemy
    if enemy~=removed and rules.inAttackRange(attacker,spot) then
      local power=rules.classes[enemy.class].power
      local loss=math.min(power,hp)+(power>=hp and 35 or 0)
      local risk=hitChance(piece)*loss
      backup=math.max(backup,math.min(worst,risk))
      worst=math.max(worst,risk)
    end
  end
  return worst+.18*backup
end

local function attackValue(piece,target,ownFort)
  local power=rules.classes[piece.class].power
  local kill=power>=target.hp
  local value=2*math.min(power,target.hp)
  if kill then value=value+23+1.8*healthBonus(piece) end
  if target.class=='fortress' then value=value+14
  elseif rules.distance(target,ownFort)<=3 then value=value+8 end
  return hitChance(target)*value,kill
end

local function choose(state,random)
  local ownFort,enemyFort=state.forts[state.turn],state.forts[3-state.turn]
  local enemies={enemyFort}
  local homeThreat=0
  for _,unit in ipairs(state.units) do
    if unit.owner~=state.turn and unit.hp>0 then
      enemies[#enemies+1]=unit
      if rules.distance(unit,ownFort)<=3 then homeThreat=homeThreat+1 end
    end
  end
  local recentMoves={}
  for i=#state.history-1,math.max(1,#state.history-11),-2 do
    local token=state.history[i]
    recentMoves[token]=(recentMoves[token] or 0)+1
  end
  local quietTurns=0
  for i=#state.history,math.max(1,#state.history-23),-1 do
    if state.history[i]:sub(1,1)=='A' then break end
    quietTurns=quietTurns+1
  end
  -- After a long stretch without combat, take more chances to break the standoff.
  local urgency=math.max(0,(quietTurns-8)/16)
  local caution=1-.65*urgency
  local originRisk={}
  local best,bestScore=nil,-math.huge
  for _,action in ipairs(rules.actions(state)) do
    if action.type=='pass' then return action end
    local piece=rules.piece(state,action.id)
    if not originRisk[piece.id] then
      originRisk[piece.id]=danger(piece,piece,piece.hp,enemies)
    end
    local score
    if action.type=='attack' then
      local target=rules.occupied(state,action.r,action.c).ref
      local value,kill=attackValue(piece,target,ownFort)
      if kill and target==enemyFort then return action end
      local armedFort=target==enemyFort and target or nil
      local missRisk=danger(piece,piece,piece.hp,enemies,nil,armedFort)
      local hitRisk=missRisk
      if kill then
        hitRisk=0
        for roll=1,rules.DIE do
          local healed=math.min(piece.hp+roll,rules.classes[piece.class].hp)
          hitRisk=hitRisk+danger(piece,piece,healed,enemies,target)/rules.DIE
        end
      end
      local odds=hitChance(target)
      local replyRisk=odds*hitRisk+(1-odds)*missRisk
      score=value+caution*(.85*(originRisk[piece.id]-replyRisk)-.35*replyRisk)+12*urgency
    else
      local from=rules.distance(piece,enemyFort)
      local to=rules.distance(action,enemyFort)
      local homeDist=rules.distance(action,ownFort)
      local risk=danger(piece,action,piece.hp,enemies)
      local nextAttack=0
      local destination={r=action.r,c=action.c,class=piece.class,owner=piece.owner}
      for _,target in ipairs(enemies) do
        if rules.inAttackRange(destination,target) then
          local value=attackValue(piece,target,ownFort)
          nextAttack=math.max(nextAttack,value)
        end
      end
      score=math.min(3,from-to)*4.8+(to<=3 and 3 or 0)
        +caution*(1.45*(originRisk[piece.id]-risk)-.35*risk)+(.14+.14*urgency)*nextAttack
      if homeThreat>0 and homeDist<=3 then
        local closing=rules.distance(piece,ownFort)-homeDist
        score=score+math.max(0,closing)*math.min(3,homeThreat)
      end
      score=score-7*(recentMoves[rules.encode(action)] or 0)
      local previous=state.previous
      if previous and previous.actor==state.turn and previous.type=='move' and previous.id==piece.id
        and action.r==previous.from.r and action.c==previous.from.c then
        score=score-(risk>=originRisk[piece.id] and 17 or 4)
      end
    end
    score=score+random()*1.1
    if score>bestScore then best,bestScore=action,score end
  end
  return best
end

return choose
