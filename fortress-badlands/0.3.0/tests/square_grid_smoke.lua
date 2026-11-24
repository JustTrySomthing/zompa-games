package.path='./?.lua;'..package.path
local R=require('rules')
assert(R.ROWS==12 and R.COLS==7)
local s=R.new(2206)
assert(#s.units==20 and R.count(s,1)==10 and R.count(s,2)==10)
assert(s.forts[1].r==11 and s.forts[2].r==0)
local seen={}
for _,u in ipairs(s.units) do
  local cell=R.key(u.r,u.c)
  assert(not seen[cell], 'no duplicate unit at start')
  seen[cell]=true
end
for _,f in ipairs(s.forts) do assert(not seen[R.key(f.r,f.c)]) end
for i=1,10 do
  local a,b=s.units[i],s.units[i+10]
  assert(a.class==b.class and a.c==b.c and a.r+b.r==11,'starting formation must mirror exactly')
end
for r=0,11 do
  for c=0,6 do
    local k=R.key(r,c)
    local r1,c1=R.fromkey(k)
    assert(r1==r and c1==c)
    local n=R.neighbors(r,c)
    local expected=((r==0 or r==11) and 2 or 3)*((c==0 or c==6) and 2 or 3)-1
    assert(#n==expected,('bad neighbor count %d,%d: %d vs %d'):format(r,c,#n,expected))
    for _,v in ipairs(n) do assert(R.distance({r=r,c=c},v)==1) end
  end
end
-- A diagonal step now costs one move; a distant square cannot be reached beyond Move.
local a,b=s.units[1],s.units[11]
for _,u in ipairs(s.units) do u.hp=0 end
s.turn=1;a.hp=R.classes[a.class].hp;b.hp=R.classes[b.class].hp
-- Knight can attack a soldier across a 3-square diagonal on a completely clear board.
a.r,a.c=6,1;b.r,b.c=3,4
local target=R.key(b.r,b.c)
assert(R.distance(a,b)==3 and R.attacks(s,a.id)[target])
assert(#R.route(s,a.id,b.r,b.c)==4)
assert(not R.attacks(s,a.id)[R.key(2,5)])
-- Routes must not pass through occupied allies.
for _,u in ipairs(s.units) do if u.id~=1 and u.id~=11 then u.hp=0 end end
for _,point in ipairs(R.neighbors(a.r,a.c)) do
  local id=2
  while id<=10 and s.units[id].hp>0 do id=id+1 end
  assert(id<=10)
  local block=s.units[id];block.owner=1;block.hp=R.classes[block.class].hp;block.r=point.r;block.c=point.c
end
assert(not R.attacks(s,a.id)[target], 'surrounded knight cannot jump over friends')
assert(not R.route(s,a.id,b.r,b.c))
local initial=R.new(105)
local saved=R.serialize(initial)
assert(saved:sub(1,3)=='v3|' and R.restore(saved))
assert(not R.restore(saved:gsub('^v3|','v2|')),'previous geometry saves are incompatible')
print('PASS: 84 full square cells, 8-way adjacency, symmetric 10v10 layout, no clipped edges, move limits, and v3 save format')
