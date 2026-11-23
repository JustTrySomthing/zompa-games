local R=require("rules"); local S=require("save"); math.randomseed(57)
local count=0
for m=1,1200 do
 local s=R.new();local steps=0
 repeat
  local f=R.route[s.battle]
  while s.phase~="result" do
   local act=R.actions(s)
   local chosen=act[math.random(#act)]
   local preview
   if chosen.l then
    local random=math.random;math.random=function() error("Preview used randomness") end
    preview=R.preview(s,chosen)
    math.random=random
   end
   assert(R.play(s,chosen));R.validate(s)
   if preview then for seat=1,2 do for l=1,3 do
    assert(R.total(preview.p[seat],l)==R.total(s.p[seat],l))
   end end end
   steps=steps+1
   if steps%3==0 then s=S.decode(S.encode(s)) end
   for i,p in ipairs(s.p) do
    local ids={}
    local function take(id) assert(id>=1 and id<=18 and not ids[id]);ids[id]=true end
    for _,key in ipairs({"hand","deck","discard"}) do for _,id in ipairs(p[key]) do take(id) end end
    for _,u in ipairs(p.board) do take(u.id) end
    if (s.locks[i] or 0)>0 then take(s.locks[i]) end
    for id=1,18 do assert(ids[id]) end;assert(#p.hand<=4)
   end
  end
  local r=s.history[#s.history]
  assert(r.flag[1]==R.total(s.p[1],f)+r.bonus[1])
  assert(r.flag[2]==R.total(s.p[2],f)+r.bonus[2])
  count=count+1
 until not R.advance(s)
 assert(s.battle>=3 and s.battle<=5 and math.max(s.score[1],s.score[2])==3)
end
print("1200 matches; "..count.." battles passed")
