-- Zompa Fortress Strategy: pure deterministic rules (no LÖVE dependencies).
-- All board positions are zero-based (row 0..12, column 0..6).
local M = {}
M.ROWS, M.COLS = 13, 7
M.classes = {
  warrior   = {hp=19, move=2, hit=5, name='Warrior', mark='W'},
  barbarian = {hp=25, move=1, hit=5, name='Barbarian', mark='B'},
  archer    = {hp=15, move=2, hit=7, name='Archer', mark='A'},
  wizard    = {hp=18, move=1, hit=7, name='Wizard', mark='Z'},
  knight    = {hp=15, move=3, hit=5, name='Knight', mark='K'},
}
M.FORT_HP, M.FORT_DIE, M.FORT_HIT = 35, 8, 5
M.SIEGE_DIE, M.SIEGE_HIT, M.SIEGE_HIT_AT = 8, 7, 4
local NEIGHBORS = {{1,0},{-1,0},{0,1},{0,-1},{1,-1},{-1,1}}

local function on(r,c) return r>=0 and r<M.ROWS and c>=0 and c<M.COLS end
function M.key(r,c) return r*M.COLS+c end
function M.fromkey(k) return math.floor(k/M.COLS), k%M.COLS end
local function axial(r,c) return c-math.floor(r/2), r end
local function offset(q,r) return r, q+math.floor(r/2) end
function M.distance(a,b)
  local aq,ar=axial(a.r,a.c); local bq,br=axial(b.r,b.c)
  local dq,dr=aq-bq,ar-br
  return math.max(math.abs(dq),math.abs(dr),math.abs(dq+dr))
end
function M.neighbors(r,c)
  local q,rr=axial(r,c); local result={}
  for _,d in ipairs(NEIGHBORS) do
    local nr,nc=offset(q+d[1],rr+d[2]); if on(nr,nc) then result[#result+1]={r=nr,c=nc} end
  end
  return result
end
local function cube_round(x,y,z)
  local rx,ry,rz=math.floor(x+0.5),math.floor(y+0.5),math.floor(z+0.5)
  local dx,dy,dz=math.abs(rx-x),math.abs(ry-y),math.abs(rz-z)
  if dx>dy and dx>dz then rx=-ry-rz elseif dy>dz then ry=-rx-rz else rz=-rx-ry end
  return rx,ry,rz
end
-- Hex ray through centers, rather than 'bending' around blocking soldiers.
function M.line(a,b)
  local aq,ar=axial(a.r,a.c);local bq,br=axial(b.r,b.c)
  local n=M.distance(a,b);local out={}
  if n==0 then return {{r=a.r,c=a.c}} end
  for i=0,n do
    local t=i/n;local x=aq+(bq-aq)*t+0.000001
    local z=ar+(br-ar)*t-0.000002; local y=-x-z
    local q,_,rr=cube_round(x,y,z);local r,c=offset(q,rr)
    out[#out+1]={r=r,c=c}
  end
  return out
end

-- Mirror the same balanced ten-unit formation across the Badlands.
-- Fortresses at (1,3) and (11,3).  Player 1 starts at the bottom.
local formation = {
  {r=8,c=3,class='knight'},
  {r=9,c=0,class='knight'}, {r=9,c=2,class='warrior'},
  {r=9,c=4,class='warrior'}, {r=9,c=6,class='archer'},
  {r=10,c=1,class='barbarian'}, {r=10,c=2,class='archer'},
  {r=10,c=3,class='wizard'}, {r=10,c=4,class='warrior'},
  {r=10,c=5,class='barbarian'},
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
  local s={version=2,seed=seed,rng=seed,turn=1,moves=0,units={},
    forts={{r=11,c=3,hp=M.FORT_HP,owner=1},{r=1,c=3,hp=M.FORT_HP,owner=2}},
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
  for _,name in ipairs({'units','forts','history','last'}) do
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
-- Use normal MOVE distance for both empty landing hexes and enemy captures.
-- Every route may change directions, but cannot travel through ANY occupied hex.
local function destinations(s,id)
  local u=s.units[id]
  if not u or u.hp<=0 or u.owner~=s.turn or s.winner~=nil then return {},{},{} end
  local steps=M.classes[u.class].move
  local seen={[M.key(u.r,u.c)]=true}
  local queue={{r=u.r,c=u.c,dist=0}}
  local empty,enemy,parents={},{},{}
  local head=1
  while queue[head] do
    local cur=queue[head];head=head+1
    if cur.dist<steps then
      for _,p in ipairs(M.neighbors(cur.r,cur.c)) do
        local k=M.key(p.r,p.c)
        if not seen[k] then
          seen[k]=true
          parents[k]=M.key(cur.r,cur.c)
          local occupant=M.occupied(s,p.r,p.c)
          if not occupant then
            empty[k]=cur.dist+1
            queue[#queue+1]={r=p.r,c=p.c,dist=cur.dist+1}
          elseif occupant.owner~=u.owner then
            enemy[k]=occupant
          end
        end
      end
    end
  end
  return empty,enemy,parents
end
function M.route(s,id,r,c)
  local empty,enemy,parents=destinations(s,id)
  local target=M.key(r,c)
  if not empty[target] and not enemy[target] then return nil end
  local u=s.units[id]
  local origin=M.key(u.r,u.c)
  local reversed={};local k=target
  for step=1,M.classes[u.class].move+1 do
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
  if M.count(s,s.turn)==0 then return {{type='pass'}} end
  local actions={}
  for _,u in ipairs(s.units) do
    if u.owner==s.turn and u.hp>0 then
      for k,_ in pairs(M.moves(s,u.id)) do
        local r,c=M.fromkey(k);actions[#actions+1]={type='move',id=u.id,r=r,c=c}
      end
      for k,_ in pairs(M.attacks(s,u.id)) do
        local r,c=M.fromkey(k);actions[#actions+1]={type='attack',id=u.id,r=r,c=c}
      end
    end
  end
  table.sort(actions,function(a,b)
    if a.id~=b.id then return (a.id or 0)<(b.id or 0) end
    if a.type~=b.type then return a.type<b.type end
    if a.r~=b.r then return a.r<b.r end
    return a.c<b.c
  end)
  return actions
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
function M.apply(s,act)
  if s.winner then return false,'Game already ended.' end
  if type(act)~='table' or type(act.type)~='string' then return false,'Missing action.' end
  local player=s.turn
  local event={actor=player,type=act.type}
  if act.type=='pass' then
    if M.count(s,player)>0 then return false,'Pass is allowed only with no soldiers.' end
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
      while u.hp>0 and defender.hp>0 do
        local a,b=next_random(s,8),next_random(s,8)
        local who,damage='tie',0
        if a>b then
          who,damage='attacker',aHit
          defender.hp=math.max(0,defender.hp-damage)
        elseif b>a then
          who,damage='defender',dHit
          u.hp=math.max(0,u.hp-damage)
        end
        event.rounds[#event.rounds+1]={a=a,b=b,who=who,damage=damage,
          attackerHp=u.hp,defenderHp=defender.hp}
      end
      -- In the new contested-hex combat only one combatant can die.
      event.attackerHpEnd=u.hp;event.defenderHpEnd=defender.hp
      if target.kind=='fort' and defender.hp<=0 then
        s.winner=player;s.finish='fortress'
      end
      if target.kind=='unit' and defender.hp>0 and u.hp==0 then
        local heal=next_random(s,7)+3
        defender.hp=math.min(M.classes[defender.class].hp,defender.hp+heal)
        event.heal={owner=defender.owner,roll=heal,actual=defender.hp-event.defenderHpEnd}
      elseif u.hp>0 and defender.hp<=0 then
        if target.kind=='unit' then
          -- Capturing replaces the defender with the attacker, as in Chess.
          u.r,u.c=act.r,act.c
          event.captured=true
          local heal=next_random(s,7)+3
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
  end
  event.winner=s.winner;event.finish=s.finish
  s.last=event;s.turn=3-player
  return true,event
end
function M.encode(a)
  if a.type=='pass' then return 'P' end
  return ('%s%d_%d_%d'):format(a.type=='move' and 'M' or 'A',a.id,a.r,a.c)
end
function M.decode(token)
  if token=='P' then return {type='pass'} end
  if type(token)~='string' then return nil end
  local kind,id,r,c=token:match('^([MA])(%d+)_(%d+)_(%d+)$')
  if not kind then return nil end
  id,r,c=tonumber(id),tonumber(r),tonumber(c)
  if not id or id<1 or id>20 or not on(r,c) then return nil end
  return {type=kind=='M' and 'move' or 'attack',id=id,r=r,c=c}
end
function M.replay(seed,history)
  local s=M.new(seed)
  for i,tok in ipairs(history) do
    if s.winner then return nil,'Action after game ended at move '..i end
    local action=M.decode(tok)
    if not action then return nil,'Malformed token at move '..i end
    local ok,err=M.apply(s,action)
    if not ok then return nil,'Illegal move '..i..': '..err end
  end
  return s
end
function M.serialize(s)
  return 'v2|'..tostring(s.seed)..'|'..table.concat(s.history,',')
end
function M.restore(data)
  if type(data)~='string' or #data>262144 then return nil,'Invalid save.' end
  local seed,str=data:match('^v2|(%d+)|(.*)$')
  if not seed or #seed>12 then return nil,'Unrecognized save version.' end
  local tokens={};for t in str:gmatch('[^,]+') do tokens[#tokens+1]=t end
  if #tokens>512 then return nil,'Too many turns.' end
  return M.replay(tonumber(seed),tokens)
end
return M
)
  if not seed or #seed>12 then return nil,'Unrecognized save version.' end
  local tokens={};for t in str:gmatch('[^,]+') do tokens[#tokens+1]=t end
  if #tokens>512 then return nil,'Too many turns.' end
  return M.replay(tonumber(seed),tokens)
end
return M
