package.path='./?.lua;'..package.path
local r=require('rules')
local function scene(id,distance)
  local s=r.new(11732)
  for _,u in ipairs(s.units) do u.hp=0 end
  local a,b=s.units[id],s.units[11]
  a.r,a.c,a.hp=6,3,r.classes[a.class].hp
  b.r,b.c,b.hp=6,3+distance,r.classes[b.class].hp
  s.turn=1
  return s,a,b
end
for _,x in ipairs({{1,3},{3,2},{5,2},{8,1},{6,1}}) do
  local s,a,b=scene(x[1],x[2])
  local k=r.key(b.r,b.c)
  assert(r.attacks(s,a.id)[k],a.class..' must reach enemy using MOVE')
  assert(not r.moves(s,a.id)[k],'occupied hex is not empty move')
  local route=assert(r.route(s,a.id,b.r,b.c))
  assert(#route==x[2]+1)
  for i=2,#route do assert(r.distance(route[i-1],route[i])==1) end
  assert(not r.apply(s,{type='move',id=a.id,r=b.r,c=b.c}))
end
local s,a,b=scene(1,2)
for i,p in ipairs(r.neighbors(6,3)) do
  local u=s.units[i+1];u.hp=r.classes[u.class].hp;u.owner=1;u.r=p.r;u.c=p.c
end
assert(not r.attacks(s,1)[r.key(b.r,b.c)],'surrounded unit may not jump')
assert(not r.route(s,1,b.r,b.c))
local s,a,b=scene(3,1)
local new=nil
for k in pairs(r.moves(s,3)) do new=k;break end
assert(new)
local nr,nc=r.fromkey(new)
local oldA,oldB=a.hp,b.hp
local ok,event=r.apply(s,{type='move',id=3,r=nr,c=nc})
assert(ok and event.type=='move' and a.hp==oldA and b.hp==oldB)
local fresh=r.new(1234)
local fk=next(r.moves(fresh,1));local fr,fc=r.fromkey(fk)
assert(r.apply(fresh,{type='move',id=1,r=fr,c=fc}))
local data=r.serialize(fresh)
assert(data:sub(1,3)=='v2|')
assert(not r.restore(data:gsub('^v2|','v1|')))
assert(r.restore(data))
print('PASS: shared move/attack range, blocked paths, no adjacency auto-attack, versioned replay')
