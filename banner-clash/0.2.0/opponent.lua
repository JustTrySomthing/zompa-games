local R=require("rules")
local O={}
function O.reinforcement(s)
    local pick={kind="Hold"}
    local power=0
    for h,id in ipairs(s.p[2].hand) do
        local strength=R.power[R.kind(id)]
        if strength and strength>power then pick={kind="Reinforce",h=h};power=strength end
    end
    return pick
end
function O.move(s)
    local flag=R.route[s.battle]
    local nextSite=R.route[s.battle+1]
    if s.score[1]==2 and s.score[2]==2 then nextSite=nil end
    local chosen,best
    for _,a in ipairs(R.actions(s)) do
        local view=R.preview(s,a)
        local value=0
        for l=1,3 do
            local diff=R.total(view.p[2],l)-R.total(view.p[1],l)
            if l==flag then value=value+diff/(1+math.abs(diff)/12)
            elseif l==nextSite then value=value+.4*diff
            else value=value+.1*diff end
        end
        if a.kind=="Swap" then value=value+.03 end
        if best==nil or value>best then best=value;chosen=a end
    end
    return chosen
end
return O
