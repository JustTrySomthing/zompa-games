-- Zompa Fortress Strategy: pure deterministic rules (no LÖVE dependencies).
-- Board positions are zero-based (row 0..10, column 0..6); row widths vary.
local M = {}
M.ROWS, M.COLS = 11, 7
M.rowWidths = {3,4,5,6,7,6,7,6,5,4,3}
M.classes = {
  soldier   = {hp=22, move=1, forward=true, hit=5, name='Soldier', mark='S'},
  wizard    = {hp=24, move=2, hit=8, name='Wizard', mark='W'},
  assassin  = {hp=24, straight=true, hit=8, name='Assassin', mark='A'},
  archer    = {hp=20, move=4, straight=true, jumps=true, hit=5, name='Archer', mark='R'},
  barbarian = {hp=32, move=2, hit=8, name='Barbarian', mark='B'},
  ogre      = {hp=28, move=1, hit=10, name='Ogre', mark='O'},
}
M.FORT_HP, M.FORT_DIE, M.FORT_HIT = 50, 8, 5
M.SIEGE_DIE, M.SIEGE_HIT, M.SIEGE_HIT_AT = 8, 7, 4
-- True tessellated hex footprint. Each row is indexed left to right, so
-- neighboring row centers shift by half of one horizontal hex pitch.
function M.playable(r,c)
  return type(r)=='number' and type(c)=='number' and r%1==0 and c%1==0
    and r>=0 and r<M.ROWS and c>=0 and c<M.rowWidths[r+1]
end
local on=M.playable
function M.key(r,c) return r*M.COLS+c end
function M.fromkey(k) return math.floor(k/M.COLS), k%M.COLS end
-- Axial coordinates allow exact hex distance/adjacency despite row widths.
local function axial(r,c)
  return c+(M.COLS-M.rowWidths[r+1]-r)/2,r
end
local function column(q,r)
  return q-(M.COLS-M.rowWidths[r+1]-r)/2
end
local directions={{1,0},{-1,0},{0,1},{-1,1},{0,-1},{1,-1}}
function M.distance(a,b)
  local aq,ar=axial(a.r,a.c)
  local bq,br=axial(b.r,b.c)
  local dq,dr=aq-bq,ar-br
  return math.max(math.abs(dq),math.abs(dr),math.abs(dq+dr))
end
function M.neighbors(r,c)
  local out={}
  if not on(r,c) then return out end
  local q,rr=axial(r,c)
  for _,d in ipairs(directions) do
    local nr=rr+d[2]
    if nr>=0 and nr<M.ROWS then
      local nc=column(q+d[1],nr)
      if on(nr,nc) then out[#out+1]={r=nr,c=nc} end
    end
  end
  return out
end
function M.line(a,b)
  -- Display-only shortest geometric line for future line-of-sight features.
  -- Captures use the actual obstacle-aware BFS route, not this line.
  local n=M.distance(a,b);local out={}
  if n==0 then return {{r=a.r,c=a.c}} end
  for i=0,n do
    local t=i/n
    out[#out+1]={r=math.floor(a.r+(b.r-a.r)*t+.5),c=math.floor(a.c+(b.c-a.c)*t+.5)}
  end
  return out
end

-- Approved 11-row hourglass board: 56 joined hexagons and 15 troops
-- plus the two-tower fortress per kingdom. Top and bottom mirror exactly.
-- Red is bottom (rows 7-10), Blue is top (rows 0-3).
local formation = {
  -- Rearmost row: Barbarian / Fortress / Barbarian.
  {r=10,c=0,class='barbarian'}, {r=10,c=2,class='barbarian'},
  -- Four-hex rank: Wizard / Archer / Archer / Wizard.
  {r=9,c=0,class='wizard'}, {r=9,c=1,class='archer'},
  {r=9,c=2,class='archer'}, {r=9,c=3,class='wizard'},
  -- Five-hex rank: Ogre / Assassin / Barbarian / Assassin / Ogre.
  {r=8,c=0,class='ogre'}, {r=8,c=1,class='assassin'},
  {r=8,c=2,class='barbarian'}, {r=8,c=3,class='assassin'},
  {r=8,c=4,class='ogre'},
  -- Front rank: four Soldiers, with both flanks open.
  {r=7,c=1,class='soldier'}, {r=7,c=2,class='soldier'},
  {r=7,c=3,class='soldier'}, {r=7,c=4,class='soldier'},
}
M.formation=formation

local function next_random(s,n)
  s.rng=(s.rng*48271)%2147483647
  return 1+(s.rng%n)
end
M.next_random=next_random
function M.new(seed)
  seed=math.floor(tonumber(seed) or 1489967)%2147483647
  if seed<1 then seed=1 end
  local s={version=14,seed=seed,rng=seed,turn=1,moves=0,units={},
    forts={{r=10,c=1,hp=M.FORT_HP,owner=1},{r=0,c=1,hp=M.FORT_HP,owner=2}},
    winner=nil,finish=nil,history={},last=nil}
  for player=1,2 do
    for _,p in ipairs(formation) do
      local r=player==1 and p.r or (M.ROWS-1-p.r)
      s.units[#s.units+1]={id=#s.units+1,owner=player,r=r,c=p.c,
        class=p.class,hp=M.classes[p.class].hp}
    end
  end
  return s
end
function M.copy(s)
  local d={}
  for k,v in pairs(s) do
    if type(v)~='table' then d[k]=v end
  end
  local function copy(t)
    local n={};for k,v in pairs(t) do n[k]=type(v)=='table' and copy(v) or v end;return n
  end
  for _,name in ipairs({'units','forts','history','last','previous'}) do
    if s[name] then d[name]=copy(s[name]) end
  end
  return d
end
function M.count(s,owner)
  local n=0;for _,u in ipairs(s.units) do if u.owner==owner and u.hp>0 then n=n+1 end end
  return n
end
function M.occupied(s,r,c)
  for _,f in ipairs(s.forts) do if f.r==r and f.c==c then return {kind='fort',ref=f,owner=f.owner} end end
  for _,u in ipairs(s.units) do if u.hp>0 and u.r==r and u.c==c then return {kind='unit',ref=u,owner=u.owner} end end
end
-- Move and capture endpoints share the same per-class movement rules.
-- Wizard: teleport to any hex within 2 hex steps regardless of intervening
-- troops; cannot land on an ally and must still fight an occupied enemy hex.
-- All other troops use obstruction-aware breadth-first search as before.
local function destinations(s,id,ignoreTurn)
  local u=s.units[id]
  if not u or u.hp<=0 or (not ignoreTurn and u.owner~=s.turn) or s.winner~=nil then return {},{} end
  local class=M.classes[u.class]
  local steps=class.move
  local empty,enemy,parents={},{},{}
  local origin=M.key(u.r,u.c)
  local function mark(r,c,dist,parent)
    local k=M.key(r,c)
    local occupant=M.occupied(s,r,c)
    if occupant and occupant.owner==u.owner then return false,occupant end
    parents[k]=parent
    if occupant then enemy[k]=occupant else empty[k]=dist end
    return occupant==nil,occupant
  end

  if class.forward then
    local forwardRow=u.r+(u.owner==1 and -1 or 1)
    for _,target in ipairs(M.neighbors(u.r,u.c)) do
      if target.r==forwardRow then mark(target.r,target.c,1,origin) end
    end
    return empty,enemy,parents
  end

  if class.straight then
    local q0,r0=axial(u.r,u.c)
    for _,direction in ipairs(directions) do
      local parent=origin
      local q,r=q0,r0
      local distance=0
      while not steps or distance<steps do
        q,r=q+direction[1],r+direction[2]
        if r<0 or r>=M.ROWS then break end
        local c=column(q,r)
        distance=distance+1
        if not on(r,c) then break end
        local clear,occupant=mark(r,c,distance,parent)
        if not clear and (not class.jumps or occupant.kind=='fort') then break end
        -- The Archer skips occupied pieces in a single flight.
        if not class.jumps then parent=M.key(r,c) end
      end
    end
    return empty,enemy,parents
  end

  if u.class=='wizard' then
    for r=0,M.ROWS-1 do
      for c=0,M.rowWidths[r+1]-1 do
        local dist=M.distance(u,{r=r,c=c})
        if dist>0 and dist<=steps then mark(r,c,dist,origin) end
      end
    end
    return empty,enemy,parents
  end

  local seen={[origin]=true}
  local queue={{r=u.r,c=u.c,dist=0}}
  local head=1
  while queue[head] do
    local cur=queue[head];head=head+1
    if cur.dist<steps then
      for _,p in ipairs(M.neighbors(cur.r,cur.c)) do
        local k=M.key(p.r,p.c)
        if not seen[k] then
          seen[k]=true
          local clear=mark(p.r,p.c,cur.dist+1,M.key(cur.r,cur.c))
          if clear then queue[#queue+1]={r=p.r,c=p.c,dist=cur.dist+1} end
        end
      end
    end
  end
  return empty,enemy,parents
end
function M.route(s,id,r,c)
  if not on(r,c) then return nil end
  local empty,enemy,parents=destinations(s,id)
  local target=M.key(r,c)
  if not empty[target] and not enemy[target] then return nil end
  local u=s.units[id]
  local origin=M.key(u.r,u.c)
  local reversed={};local k=target
  while k do
    local row,col=M.fromkey(k)
    reversed[#reversed+1]={r=row,c=col}
    if k==origin then break end
    k=parents[k]
    if not k then return nil end
  end
  if k~=origin then return nil end
  local out={}
  for i=#reversed,1,-1 do out[#out+1]=reversed[i] end
  return out
end
-- Inspect pieces crossed by a legal teleport or straight jump. For a
-- two-step diagonal teleport, the flight can pass along a shared hex edge.
function M.jumpOver(s,id,r,c)
  local u=s.units[id]
  local class=M.classes[u.class]
  local crossed={}
  if class.jumps then
    local q0,r0=axial(u.r,u.c)
    local q1,r1=axial(r,c)
    local steps=M.distance(u,{r=r,c=c})
    for step=1,steps-1 do
      local row=r0+(r1-r0)*step/steps
      local q=q0+(q1-q0)*step/steps
      local col=column(q,row)
      local occupant=M.occupied(s,row,col)
      if occupant and occupant.kind=='unit' then crossed[M.key(row,col)]=true end
    end
  elseif u.class=='wizard' and M.distance(u,{r=r,c=c})==2 then
    for _,cell in ipairs(M.neighbors(u.r,u.c)) do
      local occupant=M.occupied(s,cell.r,cell.c)
      if occupant and occupant.kind=='unit' and M.distance(cell,{r=r,c=c})==1 then
        crossed[M.key(cell.r,cell.c)]=true
      end
    end
  end
  return crossed
end
function M.threatenedHexes(s,id)
  local empty,enemy=destinations(s,id,true)
  for k in pairs(enemy) do empty[k]=true end
  return empty
end
function M.moves(s,id)
  local empty=destinations(s,id)
  return empty
end
function M.attacks(s,id)
  local _,enemy=destinations(s,id)
  return enemy
end
function M.actions(s)
  if s.winner then return {} end
  local actions={}
  for _,u in ipairs(s.units) do
    if u.owner==s.turn and u.hp>0 then
      local empty,enemies=destinations(s,u.id)
      for k in pairs(empty) do
        local r,c=M.fromkey(k);actions[#actions+1]={type='move',id=u.id,r=r,c=c}
      end
      for k in pairs(enemies) do
        local r,c=M.fromkey(k);actions[#actions+1]={type='attack',id=u.id,r=r,c=c}
      end
    end
  end
  if #actions==0 then return {{type='pass'}} end
  table.sort(actions,function(a,b)
    if a.id~=b.id then return (a.id or 0)<(b.id or 0) end
    if a.type~=b.type then return a.type<b.type end
    if a.r~=b.r then return a.r<b.r end
    return a.c<b.c
  end)
  return actions
end
function M.mustPass(s)
  if s.winner then return false end
  for _,u in ipairs(s.units) do
    if u.owner==s.turn and u.hp>0 then
      local empty,enemies=destinations(s,u.id)
      if next(empty) or next(enemies) then return false end
    end
  end
  return true
end
local function final_siege(s)
  local records={}
  local start={h1=s.forts[1].hp,h2=s.forts[2].hp}
  while s.forts[1].hp>0 and s.forts[2].hp>0 do
    local d1,d2=next_random(s,M.SIEGE_DIE),next_random(s,M.SIEGE_DIE)
    -- Both trebuchets fire independently at once, including on equal dice.
    -- Each hit deals seven damage; both walls may collapse in the same volley.
    local hit1=(d1>=M.SIEGE_HIT_AT) and M.SIEGE_HIT or 0
    local hit2=(d2>=M.SIEGE_HIT_AT) and M.SIEGE_HIT or 0
    s.forts[1].hp=math.max(0,s.forts[1].hp-hit2)
    s.forts[2].hp=math.max(0,s.forts[2].hp-hit1)
    records[#records+1]={a=d1,b=d2,hit1=hit1,hit2=hit2,h1=s.forts[1].hp,h2=s.forts[2].hp}
  end
  s.winner=s.forts[1].hp>0 and 1 or s.forts[2].hp>0 and 2 or 0
  s.finish=s.winner==0 and 'mutual' or 'siege'
  return records,start
end
local function apply(s,act,legacyReplay)
  if s.winner then return false,'Game already ended.' end
  if type(act)~='table' or type(act.type)~='string' then return false,'Missing action.' end
  local player=s.turn
  local event={actor=player,type=act.type}
  if act.type=='pass' then
    if not M.mustPass(s) then return false,'Pass is allowed only when no legal action exists.' end
  else
    local u=s.units[act.id]
    if not u or u.hp<=0 or u.owner~=player then return false,'Invalid soldier.' end
    if not on(act.r,act.c) then return false,'Target outside battlefield.' end
    if act.type=='move' then
      if not M.moves(s,act.id)[M.key(act.r,act.c)] then return false,'Blocked or out-of-range movement.' end
      event.id=u.id;event.from={r=u.r,c=u.c};event.to={r=act.r,c=act.c}
      u.r,u.c=act.r,act.c
    elseif act.type=='attack' then
      local target=M.attacks(s,act.id)[M.key(act.r,act.c)]
      if not target then return false,'Destination blocked or beyond movement range.' end
      local defender=target.ref
      event.id=u.id;event.from={r=u.r,c=u.c};event.to={r=act.r,c=act.c}
      event.defender=target.kind
      event.attackerClass=u.class;event.attackerHpStart=u.hp
      event.defenderClass=target.kind=='fort' and 'fortress' or defender.class
      event.defenderHpStart=defender.hp
      event.rounds={}
      local aHit=M.classes[u.class].hit
      local dHit=target.kind=='fort' and M.FORT_HIT or M.classes[defender.class].hit
      local attackerHp,defenderHp=u.hp,defender.hp
      local dice={rng=s.rng}
      local firstRetreat
      local retreatAfter=act.retreatAfter
      -- v14 histories may contain a retreat from v0.5.14. Only replay can use it.
      if retreatAfter~=nil and (not legacyReplay or type(retreatAfter)~='number' or retreatAfter<1 or retreatAfter%1~=0) then
        return false,'Invalid retreat round.'
      end
      while attackerHp>0 and defenderHp>0 do
        local a,b=next_random(dice,8),next_random(dice,8)
        local who,damage='tie',0
        if a>b then
          who,damage='attacker',aHit
          defenderHp=math.max(0,defenderHp-damage)
        elseif b>a then
          who,damage='defender',dHit
          attackerHp=math.max(0,attackerHp-damage)
        end
        event.rounds[#event.rounds+1]={a=a,b=b,who=who,damage=damage,
          attackerHp=attackerHp,defenderHp=defenderHp}
        if retreatAfter and not firstRetreat and defenderHp>0 and attackerHp>0 and attackerHp*2<M.classes[u.class].hp then
          firstRetreat=#event.rounds
        end
        if retreatAfter and #event.rounds==retreatAfter then break end
      end
      if retreatAfter and retreatAfter~=firstRetreat then
        return false,'Retreat is only available at the first eligible exchange.'
      end
      u.hp,defender.hp,s.rng=attackerHp,defenderHp,dice.rng
      event.retreated=retreatAfter~=nil
      -- In the new contested-hex combat only one combatant can die.
      event.attackerHpEnd=u.hp;event.defenderHpEnd=defender.hp
      if target.kind=='fort' and defender.hp<=0 then
        s.winner=player;s.finish='fortress'
      end
      if target.kind=='unit' and defender.hp>0 and u.hp==0 then
        local heal=next_random(s,8)
        defender.hp=math.min(M.classes[defender.class].hp,defender.hp+heal)
        event.heal={owner=defender.owner,roll=heal,actual=defender.hp-event.defenderHpEnd}
      elseif u.hp>0 and defender.hp<=0 then
        if target.kind=='unit' then
          -- Capturing replaces the defender with the attacker, as in Chess.
          u.r,u.c=act.r,act.c
          event.captured=true
          local heal=next_random(s,8)
          u.hp=math.min(M.classes[u.class].hp,u.hp+heal)
          event.heal={owner=player,roll=heal,actual=u.hp-event.attackerHpEnd}
        end
      end
      event.attackerHpAfter=u.hp;event.defenderHpAfter=defender.hp
    else
      return false,'Unknown action type.'
    end
  end
  local tok=M.encode(act)
  s.history[#s.history+1]=tok;s.moves=s.moves+1
  if not s.winner and M.count(s,1)==0 and M.count(s,2)==0 then
    event.siege,event.siegeStart=final_siege(s)
  elseif act.type=='pass' and s.last and s.last.type=='pass' then
    s.winner,s.finish=0,'stalemate'
  end
  event.winner=s.winner;event.finish=s.finish
  s.previous,s.last=s.last,event
  s.turn=3-player
  return true,event
end
function M.apply(s,act)
  return apply(s,act,false)
end
function M.encode(a)
  if a.type=='pass' then return 'P' end
  local token=('%s%d_%d_%d'):format(a.type=='move' and 'M' or 'A',a.id,a.r,a.c)
  if a.type=='attack' and a.retreatAfter then return token..'_R'..a.retreatAfter end
  return token
end
function M.decode(token)
  if token=='P' then return {type='pass'} end
  if type(token)~='string' then return nil end
  local kind,id,r,c=token:match('^([MA])(%d+)_(%d+)_(%d+)$')
  local retreatAfter
  if not kind then kind,id,r,c,retreatAfter=token:match('^(A)(%d+)_(%d+)_(%d+)_R(%d+)$') end
  if not kind then return nil end
  id,r,c=tonumber(id),tonumber(r),tonumber(c)
  if not id or id<1 or id>2*#formation or not on(r,c) then return nil end
  return {type=kind=='M' and 'move' or 'attack',id=id,r=r,c=c,retreatAfter=tonumber(retreatAfter)}
end
function M.replay(seed,history,openingSeed)
  local s=M.new(openingSeed or seed)
  for i,tok in ipairs(history) do
    -- The online opener can fight before the second player's seed exists.
    if i==2 and openingSeed then s.seed,s.rng=seed,seed end
    if s.winner then return nil,'Action after game ended at move '..i end
    local action=M.decode(tok)
    if not action then return nil,'Malformed token at move '..i end
    local ok,err=apply(s,action,true)
    if not ok then return nil,'Illegal move '..i..': '..err end
  end
  return s
end
function M.serialize(s)
  return 'v14|'..tostring(s.seed)..'|'..table.concat(s.history,',')
end
function M.restore(data)
  if type(data)~='string' or #data>262144 then return nil,'Invalid save.' end
  local seed,str=data:match('^v14|(%d+)|(.*)$')
  if not seed or #seed>12 then return nil,'Unrecognized save version.' end
  local tokens={};for t in str:gmatch('[^,]+') do tokens[#tokens+1]=t end
  if #tokens>512 then return nil,'Too many turns.' end
  return M.replay(tonumber(seed),tokens)
end
return M
