local variants={row=5,potionMinHeal=3,potionMaxHeal=8,crateHealth=12}

function variants.defaults()
  return {traps=false,trapCount=3,wall=false,wallHealth=16,wallShield=3,overWall=false,
    potions=false,potionCount=2,destroyPotions=false,
    crates=false,crateCount=3,destroyCrates=false}
end

function variants.encode(options)
  local base=('%d_%d_%d_%d_%d_%d'):format(options.traps and 1 or 0,options.trapCount,
    options.wall and 1 or 0,options.wallHealth,options.wallShield,options.overWall and 1 or 0)
  if options.crates then
    return base..('_C%d_%d'):format(options.crateCount,options.destroyCrates and 1 or 0)
  end
  if options.potions then
    return base..('_%d_%d'):format(options.potionCount,options.destroyPotions and 1 or 0)
  end
  return base
end

function variants.enabled(options)
  return options.wall or options.traps or options.potions or options.crates
end

function variants.decode(value)
  if not value then return variants.defaults() end
  local classic,crates,shoot=value:match('^(.+)_C([1-9])_([01])$')
  if classic then value=classic end
  local base,potions,destroy=value:match('^(.+)_([1-3])_([01])$')
  local fields='^([01])_([1-9])_([01])_(%d%d?)_(%d%d?)_([01])$'
  if not base or not base:match(fields) then base,potions,destroy=value,nil,nil end
  local traps,count,wall,health,shield,over=base:match(fields)
  count,health,shield=tonumber(count),tonumber(health),tonumber(shield)
  if not health or health<1 or health>50 or shield>11
    or crates and (traps=='1' or potions) then return nil end
  return {traps=traps=='1',trapCount=count,wall=wall=='1',wallHealth=health,wallShield=shield,overWall=over=='1',
    potions=potions~=nil,potionCount=tonumber(potions) or 2,destroyPotions=destroy=='1',
    crates=crates~=nil,crateCount=tonumber(crates) or 3,destroyCrates=shoot=='1'}
end

function variants.setup(board,rules,options)
  board.options=variants.defaults()
  for key in pairs(board.options) do
    if options and options[key]~=nil then board.options[key]=options[key] end
  end
  board.walls,board.traps,board.potions={},{},{}
  board.crates,board.crateContents,board.scorches={},{},{}
  if board.options.wall then
    for c=0,rules.rowWidths[variants.row+1]-1 do
      board.walls[rules.key(variants.row,c)]={r=variants.row,c=c,class='wall',owner=0,
        hp=board.options.wallHealth,shield=board.options.wallShield}
    end
  end
  if board.options.traps then
    local spots={}
    for r=variants.row-1,variants.row+1 do
      for c=0,rules.rowWidths[r+1]-1 do
        local key=rules.key(r,c)
        if not board.walls[key] then spots[#spots+1]=key end
      end
    end
    -- Use a separate stream so placement never alters the combat dice.
    local random={rng=(board.seed*2381+293)%2147483646+1}
    for _=1,board.options.trapCount do
      local i=rules.next_random(random,#spots)
      board.traps[table.remove(spots,i)]=rules.next_random(random,12)
    end
  end
  if board.options.potions then
    local spots={}
    for r=variants.row-1,variants.row+1 do
      for c=0,rules.rowWidths[r+1]-1 do
        local key=rules.key(r,c)
        if not board.walls[key] and not board.traps[key] then
          spots[#spots+1]={r=r,c=c}
        end
      end
    end
    local random={rng=(board.seed*6421+919)%2147483646+1}
    for _=1,board.options.potionCount do
      local spot=table.remove(spots,rules.next_random(random,#spots))
      spot.heal=variants.potionMinHeal-1+rules.next_random(random,variants.potionMaxHeal-variants.potionMinHeal+1)
      board.potions[rules.key(spot.r,spot.c)]=spot
    end
  end
  if board.options.crates then
    local spots={}
    for r=variants.row-1,variants.row+1 do
      for c=0,rules.rowWidths[r+1]-1 do
        local key=rules.key(r,c)
        if not board.walls[key] and not board.traps[key] and not board.potions[key] then
          spots[#spots+1]={r=r,c=c}
        end
      end
    end
    -- Content and placement use separate streams, independent of combat.
    local places={rng=(board.seed*4733+109)%2147483646+1}
    local contents={rng=(board.seed*8849+431)%2147483646+1}
    for _=1,board.options.crateCount do
      local spot=table.remove(spots,rules.next_random(places,#spots))
      local key=rules.key(spot.r,spot.c)
      board.crates[key]=spot
      board.crateContents[key]=rules.next_random(contents,2)==1 and 'potion' or 'bomb'
    end
  end
end

-- Determine which section a straight shot or teleport would cross.
-- A ray on the boundary of two hexes is blocked by either intact section.
function variants.blocked(board,from,to,rules)
  if not board.options.wall then return false end
  local row=variants.row
  if from.r==row and to.r==row then
    for c=math.min(from.c,to.c)+1,math.max(from.c,to.c)-1 do
      local section=board.walls[rules.key(row,c)]
      if section and section.hp>0 then return true end
    end
    return false
  end
  if (from.r-row)*(to.r-row)>=0 then return false end
  local function centerX(p)
    return p.c+(rules.COLS-rules.rowWidths[p.r+1])/2
  end
  local x=centerX(from)+(centerX(to)-centerX(from))*(row-from.r)/(to.r-from.r)
    -(rules.COLS-rules.rowWidths[row+1])/2
  x=math.max(0,math.min(rules.rowWidths[row+1]-1,x))
  for c=math.max(0,math.ceil(x-.50001)),math.min(rules.rowWidths[row+1]-1,math.floor(x+.50001)) do
    local section=board.walls[rules.key(row,c)]
    if section and section.hp>0 then return true end
  end
  return false
end

return variants
