local R,codec,sdk=require("rules"),require("save"),require("zompa")
local g=love.graphics
local game,atlas,quads,fonts,buttons
local covered,overlay,hand,group,pending,page=true,nil,nil,nil,nil,1
local inspect,inspectPage
local err
local navy={.04,.10,.15};local panel={.10,.20,.27};local teal={.07,.39,.43};local gold={.86,.62,.24}
local function reset() hand,group,pending,page=nil,nil,nil,1 end
local function save()
    local ok=sdk.save("banner-clash-v1",codec.encode(game))
    err=not ok and "Save failed. Keep this match open." or nil
end
local function layout()
    local w,h=g.getDimensions();local scale=math.min(w/400,h/720)
    return scale,(w-400*scale)/2,(h-720*scale)/2
end
function love.load()
    math.randomseed(os.time())
    local raw=sdk.load("banner-clash-v1")
    if raw then local ok,v=pcall(codec.decode,raw);if ok then game=v end end
    if not game then game=R.new();save() end
    fonts={};quads={};atlas=g.newImage("cards.png")
    local w,h=atlas:getDimensions()
    for k=1,9 do quads[k]=g.newQuad((k-1)%3*w/3,math.floor((k-1)/3)*h/3,w/3,h/3,w,h) end
end
local function box(x,y,w,h,color) g.setColor(color);g.rectangle("fill",x,y,w,h,7,7) end
local function label(str,x,y,w,size,align)
    if not fonts[size] then fonts[size]=g.newFont(size) end
    g.setColor(1,1,1);g.setFont(fonts[size]);g.printf(str,x,y,w,align or "center")
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
    if R.play(game,a) then reset();covered=true;save() end
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
        covered=true;reset();save()
    end,teal)
end
local function render()
    button("II",8,7,44,42,function() overlay="Paused" end)
    label("Banner Clash",60,12,280,25)
    button("?",348,7,44,42,function() overlay="How to play" end)
    if inspect then
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
    if overlay then
        label(overlay,12,100,376,27)
        if overlay=="How to play" then
            label("Win three banners. Take five turns each, alternating one action at a time. Tap a card to deploy, cast or swap it. Move a character or pass using the buttons below your hand.",24,164,352,18)
            label("Then secretly reinforce with a character's printed strength, or Hold. Higher strength at the flag wins. A tie goes to combined strength elsewhere. A second tie awards both players a banner.",24,335,352,18)
            label("Pieces at the scored site retire. Other pieces stay. Rally expires. The next flag follows the route back across the board.",24,518,352,16)
        end
        button("Return",40,638,320,48,function() overlay=nil end,teal)
        return
    end
    label("Banners     P1   "..game.score[1].."     /     "..game.score[2].."   P2",8,65,384,19)
    if game.phase=="result" then result();return end
    local who=R.actor(game);local p=game.p[who]
    if covered then
        label("Pass to Player "..who,12,242,376,30)
        label(game.phase=="lock" and "Private reinforcement" or "Private hand",10,307,380,20)
        button("Show my hand",48,444,304,54,function() covered=false end,teal)
        return
    end
    local acts=R.actions(game);local f=R.route[game.battle]
    for l=1,3 do
        local y=104+(l-1)*55
        local nextSite=(game.score[1]~=2 or game.score[2]~=2) and R.route[game.battle+1]
        local suffix=l==f and "  •  Flag" or l==nextSite and "  •  Next" or ""
        box(8,y,384,48,l==f and teal or panel)
        buttons[#buttons+1]={x=8,y=y,w=384,h=48,fn=function()
            if hand and not pending then for _,a in ipairs(acts) do if a.kind=="Deploy" and a.h==hand and a.l==l then pending=a;return end end end
            inspect=l;inspectPage=0
        end}
        label(R.sites[l]..suffix,18,y+12,188,17,"left")
        label("You "..R.total(p,l).."   Rival "..R.total(game.p[3-who],l),204,y+12,179,16)
    end
    label("Player "..who.."   •   "..(game.phase=="lock" and "Secret reinforcement" or "Turn "..(math.floor(game.turn/2)+1).." of 5"),8,274,384,18)
    for h,id in ipairs(p.hand) do
        local k=R.kind(id);local x=8+(h-1)*97
        box(x,310,91,133,hand==h and teal or panel)
        g.setColor(1,1,1);g.draw(atlas,quads[k],x+3,313,0,85/(atlas:getWidth()/3),85/(atlas:getHeight()/3))
        label((R.power[k] and R.power[k].." " or "")..R.names[k],x+2,403,87,14)
        buttons[#buttons+1]={x=x,y=310,w=91,h=133,fn=function() reset();hand=h end}
    end
    if pending then
        label(summary(pending,who),10,486,380,20)
        if pending.l then
            local copy=codec.decode(codec.encode(game));R.play(copy,pending)
            label("Strength at "..R.sites[pending.l].."   You "..R.total(copy.p[who],pending.l).."   Rival "..R.total(copy.p[3-who],pending.l),8,530,384,17)
        end
        button("Cancel",8,638,92,48,function() pending=nil end)
        button(game.phase=="lock" and "Lock choice" or "Confirm move",110,638,282,48,function() commit(pending) end,teal)
        return
    end
    if not hand and not group then
        label(game.phase=="lock" and "Choose a character or hold." or "Choose a card or a board action.",8,474,384,17)
        if game.phase=="open" then button("Move",8,565,184,48,function() group="Move" end) end
        button(game.phase=="lock" and "Hold" or "Pass",208,565,184,48,function() pending=acts[1] end)
        return
    end
    label(hand and R.text[R.kind(p.hand[hand])] or "Move a deployed character",8,450,384,15)
    local list={}
    for _,a in ipairs(acts) do if (hand and a.h==hand) or (group and a.kind==group) then list[#list+1]=a end end
    if #list==0 then label("No legal action here. Choose another card.",12,511,376,17) end
    for j=(page-1)*3+1,math.min(#list,page*3) do
        local a=list[j];button(summary(a,who),8,485+((j-1)%3)*45,384,40,function() pending=a end)
    end
    button("Back",8,640,100,44,reset)
    if page>1 then button("Previous",120,640,126,44,function() page=page-1 end) end
    if page*3<#list then button("More",260,640,132,44,function() page=page+1 end) end
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
function love.focus(active) if not active then covered=true;overlay=nil;inspect=nil;reset();buttons={} end end
function love.keypressed(k) if k=="escape" then if overlay then overlay=nil else overlay="Paused" end;buttons={} end end
