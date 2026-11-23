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
    if kind=="Deploy" then table.insert(p.board,{id=c,l=action.l,r=0})
    elseif kind=="Swap" then table.insert(p.hand,draw(p));table.insert(p.discard,c)
    elseif kind~="Pass" then
        local target=(kind=="Gust" and s.p[3-who] or p).board[action.u]
        if kind=="Rally" then target.r=target.r+2 else target.l=action.l end
        if c then table.insert(p.discard,c) end
    end
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
return R
