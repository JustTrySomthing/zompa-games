local rules=require('rules')
local variants=require('variants')

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
local function danger(state,piece,spot,hp,enemies,removed,armedFort)
  local worst,backup=0,0
  for _,enemy in ipairs(enemies) do
    local attacker=enemy==armedFort and {class='fortress',owner=enemy.owner,r=enemy.r,c=enemy.c,armed=true} or enemy
    if enemy~=removed and rules.canAttack(state,attacker,spot) then
      local power=rules.classes[enemy.class].power
      local loss=math.min(power,hp)+(power>=hp and 35 or 0)
      local risk=hitChance(piece)*loss
      if rules.isCritical(hp,rules.classes[piece.class].hp)
        and rules.isCritical(enemy.hp,rules.classes[enemy.class].hp) then
        risk=.5*(hp+35)
      end
      backup=math.max(backup,math.min(worst,risk))
      worst=math.max(worst,risk)
    end
  end
  return worst+.18*backup
end

local function attackValue(piece,target,ownFort)
  if rules.isDeathMatch(piece,target) then
    local value=target.hp*2+23
    if target.class=='fortress' then value=value+46
    elseif rules.distance(target,ownFort)<=3 then value=value+8 end
    local sacrifice=piece.class=='fortress' and 70 or 27+piece.hp
    return .5*(value-sacrifice),false,.5
  end
  local power=rules.classes[piece.class].power
  local kill=power>=target.hp
  local value=2*math.min(power,target.hp)
  if kill then value=value+23+1.8*healthBonus(piece) end
  if target.class=='fortress' then value=value+14
  elseif rules.distance(target,ownFort)<=3 then value=value+8 end
  return hitChance(target)*value,kill,hitChance(target)
end

-- Planning uses public state only. A potion's Health roll and the trap map
-- belong to the rules engine and are never inspected here.
local function expectedPotionHealth(missing)
  local total=0
  for roll=variants.potionMinHeal,variants.potionMaxHeal do
    total=total+math.min(roll,missing)
  end
  return total/(variants.potionMaxHeal-variants.potionMinHeal+1)
end

local function potionClaims(board,pieces)
  local claims={}
  for _,piece in ipairs(pieces) do
    local missing=rules.classes[piece.class].hp-piece.hp
    if missing>0 then
      for key in pairs(rules.moves(board,piece.id)) do
        if board.potions[key] then
          local value=expectedPotionHealth(missing)
          if rules.isCritical(piece.hp,rules.classes[piece.class].hp) then value=value+2 end
          claims[key]=math.max(claims[key] or 0,value)
        end
      end
    end
  end
  return claims
end

local function publicTrapOdds(board)
  local visited={}
  if not board.options.traps then return 0,visited end
  local remaining=math.max(0,board.options.trapCount-(board.triggeredTraps or 0))
  for _,token in ipairs(board.history) do
    if token:sub(1,1)=='M' then
      local action=rules.decode(token)
      if action then visited[rules.key(action.r,action.c)]=true end
    end
  end
  local unknown=0
  for r=variants.row-1,variants.row+1 do
    for c=0,rules.rowWidths[r+1]-1 do
      local key=rules.key(r,c)
      if not visited[key] and not board.potions[key] and not board.walls[key] then unknown=unknown+1 end
    end
  end
  return unknown>0 and math.min(1,remaining/unknown) or 0,visited
end

local function trapCost(board,action,hp,odds,visited)
  local key=rules.key(action.r,action.c)
  if odds==0 or math.abs(action.r-variants.row)>1 or visited[key] or board.potions[key] or board.walls[key] then
    return 0
  end
  local total=0
  for damage=1,12 do
    total=total+math.min(hp,damage)+(damage>=hp and 35 or 0)
  end
  return odds*total/12
end

local function breachValue(before,after,pieces,targets,fort)
  local value=0
  for _,piece in ipairs(pieces) do
    local old=rules.moves(before,piece.id)
    local new=rules.moves(after,piece.id)
    local advance=0
    for key in pairs(new) do
      if not old[key] then
        local r,c=rules.fromkey(key)
        local closer=rules.distance(piece,fort)-rules.distance({r=r,c=c},fort)
        advance=math.max(advance,closer)
      end
    end
    value=value+advance*3
    for _,target in ipairs(targets) do
      if rules.canAttack(after,piece,target) and not rules.canAttack(before,piece,target) then
        value=value+(target==fort and 7 or 3)
        break
      end
    end
  end
  return value
end

local function choose(state,random)
  local ownFort,enemyFort=state.forts[state.turn],state.forts[3-state.turn]
  local allies,enemies={ownFort},{enemyFort}
  local fortThreats={}
  local nearby,firing=0,0
  for _,unit in ipairs(state.units) do
    if unit.hp>0 then
      if unit.owner==state.turn then
        allies[#allies+1]=unit
      else
        enemies[#enemies+1]=unit
        local distance=rules.distance(unit,ownFort)
        local canHit=rules.canAttack(state,unit,ownFort)
        if distance<=2 then nearby=nearby+1 end
        if canHit then firing=firing+1 end
        if distance<=2 or canHit then fortThreats[unit.id]=canHit and 2 or 1 end
      end
    end
  end
  local last=state.last
  local attacked=last and last.defenderClass=='fortress' and last.actor~=state.turn
  local coordinated=nearby>=3 or firing>=2
  local defense=math.min(12,nearby*1.5+firing*3)
  if coordinated then defense=defense+7 end
  if attacked then defense=defense+8
  elseif ownFort.armed and firing>0 then defense=defense+4 end
  if firing>0 and ownFort.hp<=rules.FORT_HP*.25 then defense=defense+10 end
  local recentMoves={}
  for i=#state.history-1,math.max(1,#state.history-11),-2 do
    local token=state.history[i]
    recentMoves[token]=(recentMoves[token] or 0)+1
  end
  local quietTurns=0
  for i=#state.history,math.max(1,#state.history-23),-1 do
    local kind=state.history[i]:sub(1,1)
    if kind=='A' or kind=='D' then break end
    quietTurns=quietTurns+1
  end
  -- After a long stretch without combat, take more chances to break the standoff.
  local urgency=math.max(0,(quietTurns-8)/16)
  local caution=1-.65*urgency
  local setupWeight=.14+.14*urgency
  local originRisk,breaches={},{}
  local enemyView=setmetatable({turn=3-state.turn},{__index=state})
  local ownClaims,enemyClaims
  if state.options.destroyPotions and next(state.potions) then
    ownClaims=potionClaims(state,allies)
    enemyClaims=potionClaims(enemyView,enemies)
  end
  local odds,visited=publicTrapOdds(state)
  local best,bestScore=nil,-math.huge
  for _,action in ipairs(rules.actions(state)) do
    if action.type=='pass' then return action end
    local piece=rules.piece(state,action.id)
    if not originRisk[piece.id] then
      originRisk[piece.id]=danger(state,piece,piece,piece.hp,enemies)
    end
    local score
    if action.type=='potion' then
      local key=rules.key(action.r,action.c)
      score=-6+3.2*(enemyClaims[key] or 0)-1.8*(ownClaims[key] or 0)-originRisk[piece.id]
    elseif action.type=='attack' then
      local target=rules.occupied(state,action.r,action.c).ref
      if target.class=='wall' then
        local power=rules.classes[piece.class].power
        local odds=(rules.DIE-target.shield)/rules.DIE
        local key=rules.key(action.r,action.c)
        local breach=breaches[key]
        if not breach then
          local walls={}
          for index,section in pairs(state.walls) do
            if index~=key then walls[index]=section end
          end
          local opened=setmetatable({walls=walls},{__index=state})
          local enemyOpened=setmetatable({turn=enemyView.turn,walls=walls},{__index=state})
          breach={value=breachValue(state,opened,allies,enemies,enemyFort)
            -.45*breachValue(enemyView,enemyOpened,enemies,allies,ownFort),board=opened}
          breaches[key]=breach
        end
        local opens=power>=target.hp
        local reply=opens and danger(breach.board,piece,piece,piece.hp,enemies) or originRisk[piece.id]
        local progress=power/math.max(power,target.hp)
        score=(math.min(power,target.hp)+progress*(9+math.max(-5,breach.value)))*odds
          +13*urgency-.65*(originRisk[piece.id]+odds*(reply-originRisk[piece.id]))
      else
        local value,kill,odds=attackValue(piece,target,ownFort)
        if kill and target==enemyFort then return action end
        local armedFort=target==enemyFort and target or nil
        local missRisk=danger(state,piece,piece,piece.hp,enemies,nil,armedFort)
        local hitRisk=missRisk
        if rules.isDeathMatch(piece,target) then
          hitRisk=danger(state,piece,piece,piece.hp,enemies,target)
          missRisk=0
        elseif kill then
          hitRisk=0
          for roll=1,rules.DIE do
            local healed=math.min(piece.hp+roll,rules.classes[piece.class].hp)
            hitRisk=hitRisk+danger(state,piece,piece,healed,enemies,target)/rules.DIE
          end
        end
        local replyRisk=odds*hitRisk+(1-odds)*missRisk
        score=value+caution*(.85*(originRisk[piece.id]-replyRisk)-.35*replyRisk)+12*urgency
        local threat=fortThreats[target.id]
        if threat then score=score+defense*threat*(.5+.5*odds) end
      end
    else
      local from=rules.distance(piece,enemyFort)
      local to=rules.distance(action,enemyFort)
      local hp=piece.hp
      local risk=danger(state,piece,action,hp,enemies)
      local potionValue=0
      if state.potions[rules.key(action.r,action.c)] and hp<rules.classes[piece.class].hp then
        local maximum=rules.classes[piece.class].hp
        potionValue=expectedPotionHealth(maximum-hp)
        local total=0
        for roll=variants.potionMinHeal,variants.potionMaxHeal do
          total=total+danger(state,piece,action,math.min(maximum,hp+roll),enemies)
        end
        risk=total/(variants.potionMaxHeal-variants.potionMinHeal+1)
        hp=hp+potionValue
      end
      local nextAttack,coverageGain=0,0
      local destination={r=action.r,c=action.c,class=piece.class,owner=piece.owner,hp=hp}
      for _,target in ipairs(enemies) do
        local canHit=rules.canAttack(state,destination,target)
        local covered=rules.canAttack(state,piece,target)
        -- A Barbarian closes to melee to open a new attack. The reply risk below
        -- still accounts for the defender and other enemies that can hit that hex.
        if canHit and (piece.class~='barbarian' or not covered) then
          local value=attackValue(destination,target,ownFort)
          local weight=setupWeight+(piece.class=='barbarian' and .24 or 0)
          nextAttack=math.max(nextAttack,value*weight)
        end
        local threat=fortThreats[target.id]
        if threat then
          if canHit and not covered then coverageGain=coverageGain+threat
          elseif covered and not canHit then coverageGain=coverageGain-threat end
        end
      end
      score=math.min(3,from-to)*4.8+(to<=3 and 3 or 0)
        +caution*(1.45*(originRisk[piece.id]-risk)-.35*risk)+nextAttack
      score=score+2*potionValue-trapCost(state,action,piece.hp,odds,visited)
      if defense>0 then
        local homeFrom,homeTo=rules.distance(piece,ownFort),rules.distance(action,ownFort)
        local closing=math.min(5,homeFrom)-math.min(5,homeTo)
        score=score+defense*(.32*closing+.44*math.max(-3,math.min(3,coverageGain)))
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
