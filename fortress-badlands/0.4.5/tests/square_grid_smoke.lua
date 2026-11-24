package.path='./?.lua;'..package.path
local r=require('rules')
assert(r.ROWS==10 and r.COLS==7)
local count=0
for i=0,9 do for j=0,6 do
 if r.playable(i,j) then count=count+1 end
 local mirrored=r.playable(9-i,6-j)
 assert(r.playable(i,j)==mirrored)
end end
assert(count==58)
local s=r.new(108)
for _,u in ipairs(s.units)do assert(r.playable(u.r,u.c))end
assert(r.playable(0,3) and not r.playable(0,1))
print('PASS: precise 7x10 grid mask, no clipped or phantom squares')
