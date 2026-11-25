package.path='./?.lua;'..package.path
local saved={}
love={
  graphics={},
  timer={getTime=function() return os.clock() end},
  math={random=function(a,b) if a and b then return math.random(a,b) elseif a then return math.random(a) else return math.random() end end},
  filesystem={createDirectory=function()return true end,getInfo=function(k)return saved[k] and {type='file'} end,write=function(k,v)saved[k]=v;return true end,read=function(k)return saved[k] end,remove=function(k)saved[k]=nil;return true end},
}
local G=love.graphics
for _,fn in ipairs({'setColor','printf','setFont','polygon','setLineWidth','circle','rectangle','line'}) do G[fn]=function(...) end end
G.newFont=function(size) assert(type(size)=='number' and size>0);return {size=size} end
G.newImage=function(path)
  local w,h=path=='art/board.png' and 700 or 144, path=='art/board.png' and 984 or 144
  return {getDimensions=function()return w,h end, getWidth=function()return w end, setFilter=function()end}
end
G.draw=function(...) end
local width,height=390,700
G.getDimensions=function()return width,height end
-- Mock only SDK host integration. UI code still calls the actual Zompa API names.
package.preload.zompa=function()
  return {mode=function()return 'solo',false end,
    saveSession=function(x)saved.session=x;return true end,
    loadSession=function()return saved.session end,
    clearSession=function()saved.session=nil;return true end,
    audio=function()return {update=function()end}end}
end
dofile('main.lua')
love.load()
for _,dims in ipairs({{390,700},{320,520},{420,850},{280,480},{450,980}}) do
  width,height=dims[1],dims[2]
  love.resize(width,height)
  love.draw()
  love.update(0.05)
  love.draw()
end
-- Touch a real selectable soldier on the standard layout, then draw its info.
width,height=390,700; love.resize(width,height)
-- Tap approximate lower board (do not assume code-private pixel geometry).
love.touchpressed(1,width*.5,height*.68)
love.draw()

local screenW,screenH
love.system={getOS=function() return 'Web' end}
love.window={
  getDesktopDimensions=function() return screenW,screenH end,
  setMode=function(w,h) width,height=w,h;return true end,
}
local ui=require('tests.ui_geometry')
local previousBoardW=0
for _,display in ipairs({{280,550},{360,750},{412,890},{480,960}}) do
  screenW,screenH=display[1],display[2]
  love.load()
  love.draw()
  local layout=ui.layout(love)
  assert(width==screenW,'hosted canvas should use the phone width')
  assert(height<=screenH-112,'hosted canvas must leave room for Android chrome')
  assert(layout.boardW>previousBoardW,'board should grow on a wider phone')
  assert(layout.actionY+layout.actionH+3<=height-24,'action frame clips against the viewport')
  previousBoardW=layout.boardW
end
print('PASS: desktop resize and touch, hosted board grows with screen width, action frame remains visible')
