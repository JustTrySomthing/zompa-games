local R = {}
R.names = {"Stone Guard","Fox Scout","Twins","Hill Giant","Trail Captain","Outrider","Gust","Rally","March"}
R.power = {3,2,2,4,2,3}
R.text = {"Enemy spells cannot move it.","Move directly to any site.","+2 if its friendly Twin is here.","Cannot move once deployed.","+1 with a friendly companion.","+1 when alone.","Push a movable enemy one site.","Give a friendly unit +2 this battle.","Move a friendly unit to any other site."}
R.sites = {"Bridge","Watchtower","Grove"}
R.route = {1,2,3,2,1}
local function shuffle(t)
    for i=#t,2,-1 do local j=math.random(i); t[i],t[j]=t[j],t[i] end
end
function R.kind(id) return (id-1)%9+1 end
local function draw(p)
    if #p.deck==0 then p.deck,p.discard=p.discard,{}; shuffle(p.deck) end
    return table.remove(p.deck)
end
local function refill(p)
    while #p.hand<4 do
        local c=draw(p)
        if not c then break end
        table.insert(p.hand,c)
    end
end
local function player()
    local p={hand={},board={},deck={},discard={}}
    for i=1,18 do p.deck[i]=i end
    shuffle(p.deck); refill(p)
    for _,c in ipairs(p.hand) do if R.power[R.kind(c)] then return p end end
    local i=1
    while not R.power[R.kind(p.deck[i])] do i=i+1 end
    local guaranteed=table.remove(p.deck,i)
    for _,c in ipairs(p.hand) do table.insert(p.deck,c) end
    shuffle(p.deck); p.hand={guaranteed}; refill(p)
    return p
end
function R.new(first)
    return {p={player(),player()},score={0,0},battle=1,turn=0,first=first or math.random(2),locks={},phase="open",history={}}
end
function R.actor(s)
    local opener=(s.first+s.battle-2)%2+1
    if s.phase=="lock" then return s.locks[3-opener]~=nil and opener or 3-opener end
    return (opener-1+s.turn)%2+1
end
function R.total(p,l)
    local n,twins,v=0,0,0
    for _,u in ipairs(p.board) do if u.l==l then
        n=n+1; if R.kind(u.id)==3 then twins=twins+1 end
    end end
    for _,u in ipairs(p.board) do if u.l==l then
        local k=R.kind(u.id)
        v=v+R.power[k]+u.r
        if k==3 and twins==2 then v=v+2 end
        if k==5 and n>1 or k==6 and n==1 then v=v+1 end
    end end
    return v
end
function R.actions(s)
    local a={}
    if s.phase~="open" and s.phase~="lock" then return a end
    local who=R.actor(s); local p,o=s.p[who],s.p[3-who]
    local function add(kind,h,u,l) a[#a+1]={kind=kind,h=h,u=u,l=l} end
    if s.phase=="lock" then
        add("Hold")
        for h,c in ipairs(p.hand) do if R.power[R.kind(c)] then add("Reinforce",h) end end
        return a
    end
    add("Pass")
    for h,c in ipairs(p.hand) do
        local k=R.kind(c)
        if #p.deck+#p.discard>0 then add("Swap",h) end
        if k<=6 then for l=1,3 do add("Deploy",h,nil,l) end
        else
            local board=(k==7 and o or p).board
            for i,u in ipairs(board) do
                local t=R.kind(u.id)
                if k==8 then add("Rally",h,i,u.l)
                elseif t~=4 and (k~=7 or t~=1) then
                    for l=1,3 do if l~=u.l and (k==9 or math.abs(l-u.l)==1) then add(R.names[k],h,i,l) end end
                end
            end
        end
    end
    for i,u in ipairs(p.board) do for l=1,3 do
        if R.kind(u.id)~=4 and l~=u.l and (R.kind(u.id)==2 or math.abs(l-u.l)==1) then add("Move",nil,i,l) end
    end end
    return a
end
local function resolve(s)
    local f=R.route[s.battle]; local flag,side,bonus={},{},{}
    for i,p in ipairs(s.p) do
        bonus[i]=s.locks[i]==0 and 0 or R.power[R.kind(s.locks[i])]
        flag[i]=R.total(p,f)+bonus[i]; side[i]=0
        for l=1,3 do if l~=f then side[i]=side[i]+R.total(p,l) end end
    end
    local diff=flag[1]-flag[2]
    if diff==0 then diff=side[1]-side[2] end
    if diff>=0 then s.score[1]=s.score[1]+1 end
    if diff<=0 then s.score[2]=s.score[2]+1 end
    s.history[#s.history+1]={flag=flag,other=side,bonus=bonus,site=f,award=diff==0 and 0 or diff>0 and 1 or 2}
    s.phase="result"
end
local function applyBoard(s,who,action,c)
    local p=s.p[who]
    if action.kind=="Deploy" then
        table.insert(p.board,{id=c,l=action.l,r=0})
    elseif action.u then
        local owner=action.kind=="Gust" and 3-who or who
        local unit=s.p[owner].board[action.u]
        if action.kind=="Rally" then unit.r=unit.r+2 else unit.l=action.l end
    end
end

-- A preview only needs the two public boards. Never draw or shuffle here.
function R.preview(s,action)
    local copy={p={}}
    for i,p in ipairs(s.p) do
        local board={}
        for j,u in ipairs(p.board) do board[j]={id=u.id,l=u.l,r=u.r} end
        copy.p[i]={board=board}
    end
    local who=R.actor(s)
    applyBoard(copy,who,action,action.h and s.p[who].hand[action.h])
    return copy
end

function R.play(s,action)
    local valid=false
    for _,a in ipairs(R.actions(s)) do
        if a.kind==action.kind and a.u==action.u and a.h==action.h and a.l==action.l then valid=true;break end
    end
    if not valid then return false end
    local who=R.actor(s);local p=s.p[who]
    local kind=action.kind
    local c=action.h and table.remove(p.hand,action.h)
    if s.phase=="lock" then
        s.locks[who]=c or 0
        if s.locks[1]~=nil and s.locks[2]~=nil then resolve(s) end
        return true
    end
    if kind=="Swap" then
        table.insert(p.hand,draw(p))
    else
        applyBoard(s,who,action,c)
    end
    if c and kind~="Deploy" then table.insert(p.discard,c) end
    if c then refill(p) end
    s.turn=s.turn+1
    if s.turn==10 then s.phase="lock" end
    return true
end
function R.advance(s)
    if s.phase~="result" or math.max(s.score[1],s.score[2])>=3 then return false end
    for i,p in ipairs(s.p) do
        for j=#p.board,1,-1 do local u=p.board[j]
            if u.l==R.route[s.battle] then table.insert(p.discard,table.remove(p.board,j).id) else u.r=0 end
        end
        if s.locks[i]~=0 then table.insert(p.discard,s.locks[i]) end
        refill(p)
    end
    s.battle=s.battle+1;s.turn=0;s.locks={};s.phase="open"
    return true
end
-- Validate the complete snapshot before exposing it to the renderer.
function R.validate(s)
    local function integer(v,low,high)
        assert(type(v)=="number" and v%1==0 and v>=low and v<=high)
    end
    integer(s.first,1,2);integer(s.battle,1,5);integer(s.turn,0,10)
    assert(s.phase=="open" and s.turn<10 or
           (s.phase=="lock" or s.phase=="result") and s.turn==10)
    local result=s.phase=="result"
    assert(#s.history==s.battle-(result and 0 or 1))
    local scores={0,0}
    for i,r in ipairs(s.history) do
        assert(r.site==R.route[i] and scores[1]<3 and scores[2]<3)
        for seat=1,2 do
            integer(r.bonus[seat],0,4);integer(r.flag[seat],0,150);integer(r.other[seat],0,150)
        end
        local d=r.flag[1]-r.flag[2]
        if d==0 then d=r.other[1]-r.other[2] end
        assert(r.award==(d==0 and 0 or d>0 and 1 or 2))
        if d>=0 then scores[1]=scores[1]+1 end
        if d<=0 then scores[2]=scores[2]+1 end
    end
    for seat=1,2 do
        assert(s.score[seat]==scores[seat])
        local p=s.p[seat];local ids={}
        local function count(id)
            integer(id,1,18);assert(not ids[id]);ids[id]=true
        end
        assert(#p.hand<=4)
        for _,pile in ipairs({p.hand,p.deck,p.discard}) do for _,id in ipairs(pile) do count(id) end end
        for _,u in ipairs(p.board) do
            count(u.id);assert(R.power[R.kind(u.id)]);integer(u.l,1,3);integer(u.r,0,10)
        end
        local lock=s.locks[seat]
        if result then assert(lock~=nil) end
        if lock~=nil then
            assert(s.phase~="open")
            if lock~=0 then count(lock);assert(R.power[R.kind(lock)]) end
        end
        for id=1,18 do assert(ids[id]) end
    end
    if s.phase=="lock" then
        local opener=(s.first+s.battle-2)%2+1
        assert(s.locks[opener]==nil)
    end
    return s
end
return R
