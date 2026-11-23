local R,codec,sdk=require("rules"),require("save"),require("zompa")
local g=love.graphics
local game,atlas,quads,fonts,buttons
local covered,overlay,hand,group,pending,page=true,nil,nil,nil,nil,1
local landscapes,scenes
local inspect,inspectPage
local err
local navy={.04,.10,.15};local panel={.10,.20,.27};local teal={.07,.39,.43};local gold={.86,.62,.24}
local function reset() hand,group,pending,page=nil,nil,nil,1 end
local slot="banner-clash-v1"
local solo=false
local opponent=require("opponent")
local delay=0
local previous
local function restore(raw)
    if not raw then return end
    local ok,state=pcall(function() return R.validate(codec.decode(raw)) end)
    if ok then return state end
end
local function save()
    local raw=codec.encode(game)
    if previous and not sdk.save(slot.."-backup",previous) then
        err="Could not back up this match.";return
    end
    local ok=sdk.save(slot,raw)
    if ok then previous=raw end
    err=not ok and "Save failed. Keep this match open." or nil
end
local function layout()
    local w,h=g.getDimensions();local scale=math.min(w/400,h/720)
    return scale,(w-400*scale)/2,(h-720*scale)/2
end
function love.load()
    math.randomseed(os.time())
    local host=io.open("/zompado/mode","r")
    if host then solo=host:read(16)=="solo";host:close() end
    slot=solo and "banner-clash-solo" or "banner-clash-v1"
    covered=not solo
    local raw=sdk.load(slot)
    game=restore(raw)
    if not game then raw=sdk.load(slot.."-backup");game=restore(raw) end
    previous=game and raw or nil
    if not game then game=R.new();save() end
    fonts={};quads={};atlas=g.newImage("cards.png")
    landscapes=g.newImage("sites.png");scenes={}
    local sw,sh=landscapes:getDimensions()
    for i=1,3 do scenes[i]=g.newQuad(0,(i-1)*sh/3,sw,sh/3,sw,sh) end
    local w,h=atlas:getDimensions()
    for k=1,9 do quads[k]=g.newQuad((k-1)%3*w/3,math.floor((k-1)/3)*h/3,w/3,h/3,w,h) end
end
local function box(x,y,w,h,color) g.setColor(color);g.rectangle("fill",x,y,w,h,7,7) end
local function label(str,x,y,w,size,align,color)
    if not fonts[size] then fonts[size]=g.newFont(size) end
    g.setColor(color or {1,1,1});g.setFont(fonts[size]);g.printf(str,x,y,w,align or "center")
end
local function button(str,x,y,w,h,fn,color,size)
    box(x,y,w,h,color or panel);label(str,x+3,y+7,w-6,size or 16)
    buttons[#buttons+1]={x=x,y=y,w=w,h=h,fn=fn}
end
local function summary(a,who)
    local u=a.u and (a.kind=="Gust" and game.p[3-who] or game.p[who]).board[a.u]
    local target=u and (R.names[R.kind(u.id)].." #"..u.id.." at "..R.sites[u.l]) or ""
    if a.kind=="Move" or a.kind=="March" or a.kind=="Gust" then return target.." > "..R.sites[a.l] end
    if a.kind=="Rally" then return "+2 "..target end
    if a.kind=="Deploy" then return "Play at "..R.sites[a.l] end
    return a.kind
end
local function commit(a)
    local actor=R.actor(game)
    local who=solo and (actor==1 and "You" or "Computer") or ("P"..actor)
    local last
    if game.phase=="open" then
        local card=a.h and R.names[R.kind(game.p[actor].hand[a.h])]
        if a.kind=="Pass" then last=who.." passed."
        elseif a.kind=="Swap" then last=who.." swapped a card."
        elseif a.kind=="Move" then last=who.." moved to "..R.sites[a.l].."."
        else last=who.." played "..card.." at "..R.sites[a.l].."." end
    end
    if R.play(game,a) then
        game.lastMove=last;reset();covered=not solo;delay=0
        if solo and game.phase=="lock" and not game.computerChoice then
            game.computerChoice=opponent.reinforcement(game)
        end
        save()
    end
end
local function result()
    local r=game.history[#game.history]
    local winner=r.award==0 and "Both earn a banner" or "Player "..r.award.." earns the banner"
    label(R.sites[r.site],10,132,380,30)
    local function revealed(i) local id=game.locks[i];return id==0 and "Hold" or R.names[R.kind(id)] end
    label("P1 "..revealed(1).."   /   P2 "..revealed(2),8,170,384,16)
    label("Reinforcements   +"..r.bonus[1].."   /   +"..r.bonus[2],12,200,376,19)
    label("Final strength   "..r.flag[1].."  -  "..r.flag[2],12,245,376,24)
    if r.flag[1]==r.flag[2] then label("Other sites   "..r.other[1].."  -  "..r.other[2],12,295,376,18) end
    label(winner,10,365,380,22)
    local done=math.max(game.score[1],game.score[2])>=3
    if done then
        label(game.score[1]==game.score[2] and "Match drawn" or ("Player "..(game.score[1]>game.score[2] and 1 or 2).." wins!"),8,440,384,28)
    end
    button(done and "Rematch" or "Next battle",40,600,320,50,function()
        if done then game=R.new(3-game.first) else R.advance(game) end
        game.computerChoice=nil;game.lastMove=nil;covered=not solo;reset();save()
    end,teal)
end
local function render()
    if inspect and not overlay then
        label(R.sites[inspect],8,95,384,24)
        local rows={}
        for seat,player in ipairs(game.p) do for _,u in ipairs(player.board) do if u.l==inspect then
            local name=R.names[R.kind(u.id)]
            rows[#rows+1]="P"..seat.."   "..name.." #"..u.id.."   "..(u.r>0 and ("Rally +"..u.r) or "")
        end end end
        if #rows==0 then label("No characters here",8,175,384,18) end
        for j=inspectPage*8+1,math.min(#rows,inspectPage*8+8) do label(rows[j],16,160+(j-1)%8*45,368,17,"left") end
        if inspectPage>0 then button("Previous",10,565,125,44,function() inspectPage=inspectPage-1 end) end
        if #rows>(inspectPage+1)*8 then button("More",260,565,125,44,function() inspectPage=inspectPage+1 end) end
        button("Return",40,638,320,48,function() inspect=nil end,teal);return
    end
    box(8,9,384,49,panel)
    label("BANNERS",19,24,90,15,"left")
    label((solo and "You" or "P1").."  "..game.score[1].."     /     "..game.score[2].."  "..(solo and "Rival" or "P2"),115,20,258,20,"right")
    if game.phase=="result" then result();return end
    local who=R.actor(game);local p=game.p[who]
    local thinking=solo and who==2
    local viewer=solo and 1 or who
    if covered then
        label("Pass to Player "..who,12,242,376,30)
        label(game.phase=="lock" and "Private reinforcement" or "Private hand",10,307,380,20)
        button("Show my hand",48,444,304,54,function() covered=false end,teal)
        return
    end
    local acts=R.actions(game);local f=R.route[game.battle]
    local preview=pending and pending.l and R.preview(game,pending)
    local nextSite=(game.score[1]~=2 or game.score[2]~=2) and R.route[game.battle+1]
    for l=1,3 do
        local y=77+(l-1)*72
        local marked=pending and pending.l==l
        box(8,y,384,65,marked and teal or panel)
        g.setColor(1,1,1)
        g.draw(landscapes,scenes[l],12,y+4,0,100/landscapes:getWidth(),57/(landscapes:getHeight()/3))
        local badge=l==f and (nextSite and "CURRENT BATTLE" or "FINAL BATTLE") or (l==nextSite and "NEXT BATTLE" or "")
        label(badge,120,y+6,155,12,"left",l==f and gold or nil);label(R.sites[l],120,y+25,145,21,"left")
        local function strength(seat)
            local value=R.total(game.p[seat],l)
            local after=preview and R.total(preview.p[seat],l)
            return after and after~=value and (value.." → "..after) or tostring(value)
        end
        label("You  "..strength(viewer),258,y+8,125,17,"right")
        label("Rival  "..strength(3-viewer),258,y+35,125,16,"right")
        if not thinking then
            buttons[#buttons+1]={x=8,y=y,w=384,h=65,fn=function()
                if hand and not pending then for _,a in ipairs(acts) do if a.kind=="Deploy" and a.h==hand and a.l==l then pending=a;return end end end
                inspect=l;inspectPage=0
            end}
        end
    end
    if thinking then label("Computer is choosing…",12,322,376,22);return end
    local phase=game.phase=="lock" and "Secret reinforcement" or ("Turn "..(math.floor(game.turn/2)+1).." of 5")
    label((solo and "Your turn" or "Player "..who).."   •   "..phase,8,300,384,18)
    for h,id in ipairs(p.hand) do
        local k=R.kind(id);local x=8+(h-1)*97
        box(x,335,91,130,hand==h and teal or panel)
        g.setColor(1,1,1);g.draw(atlas,quads[k],x+3,338,0,85/(atlas:getWidth()/3),85/(atlas:getHeight()/3))
        if R.power[k] then
            box(x+4,341,25,25,navy);label(tostring(R.power[k]),x+4,343,25,17)
        end
        label(R.names[k],x+2,427,87,14)
        buttons[#buttons+1]={x=x,y=335,w=91,h=130,fn=function() reset();hand=h end}
    end
    if pending then
        local choice=summary(pending,who)
        if pending.h then label(R.names[R.kind(p.hand[pending.h])],10,500,380,21) end
        button("Cancel",8,636,92,52,function() pending=nil end)
        if pending.u then label(choice,12,548,376,17) end
        button(game.phase=="lock" and "Lock choice" or pending.u and ("Confirm "..pending.kind:lower()) or choice,108,636,284,52,function() commit(pending) end,teal)
        return
    end
    if not hand and not group then
        label(game.phase=="lock" and "Choose a character or hold." or "Tap a card to play.",8,485,384,18)
        if game.lastMove then label(game.lastMove,12,531,376,15) end
        if game.phase=="open" then button("Move",8,565,184,48,function() group="Move" end) end
        button(game.phase=="lock" and "Hold" or "Pass",208,565,184,48,function() pending=acts[1] end)
        return
    end
    if hand and game.phase=="open" and R.power[R.kind(p.hand[hand])] then
        label("Choose a location above.",8,491,384,22)
        label(R.text[R.kind(p.hand[hand])],8,535,384,16)
        button("Back",8,636,100,48,reset)
        for _,a in ipairs(acts) do if a.kind=="Swap" and a.h==hand then
            button("Swap card",244,636,148,48,function() pending=a end);break
        end end
        return
    end
    label(hand and R.text[R.kind(p.hand[hand])] or "Move a deployed character",8,469,384,15)
    local list={}
    for _,a in ipairs(acts) do if (hand and a.h==hand) or (group and a.kind==group) then list[#list+1]=a end end
    if #list==0 then label("No legal action here. Choose another card.",12,511,376,17) end
    for j=(page-1)*3+1,math.min(#list,page*3) do
        local a=list[j];button(summary(a,who),8,505+((j-1)%3)*45,384,40,function() pending=a end)
    end
    button("Back",8,640,100,44,reset)
    if page>1 then button("Previous",120,640,126,44,function() page=page-1 end) end
    if page*3<#list then button("More",260,640,132,44,function() page=page+1 end) end
end
function love.update(dt)
    if not solo or overlay or inspect or game.phase=="result" or R.actor(game)~=2 then return end
    delay=delay+dt
    if delay<0.45 then return end
    local action
    if game.phase=="lock" then action=game.computerChoice or opponent.reinforcement(game)
    else action=opponent.move(game) end
    commit(action)
end
function love.draw()
    buttons={};local s,x,y=layout();g.clear(navy);g.push();g.translate(x,y);g.scale(s);render()
    if err then label(err,5,697,390,13) end
    g.pop()
end
function love.mousepressed(x,y,b)
    if b~=1 then return end
    local s,ox,oy=layout();x=(x-ox)/s;y=(y-oy)/s
    for _,v in ipairs(buttons or {}) do if x>=v.x and x<v.x+v.w and y>=v.y and y<v.y+v.h then buttons={};v.fn();return end end
end
function love.focus(active) if not active then covered=not solo;overlay=nil;inspect=nil;reset();buttons={} end end
function love.keypressed(k)
    if k~="escape" and k~="acback" then return end
    if overlay then overlay=nil
    elseif inspect then inspect=nil
    elseif pending then pending=nil
    elseif hand or group then reset()
    end
    buttons={}
end
