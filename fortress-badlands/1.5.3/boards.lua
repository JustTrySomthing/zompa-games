-- Board identifiers and wire codes are stable across saved and online matches.
local boards={
  {id='classic',name='Classic',description='Full armies on the original battlefield.',
    rows={3,4,5,6,7,6,7,6,5,4,3},crateCount=3},
  {id='skirmish',name='Skirmish',description='Six troops per side for a quicker match.',
    rows={4,5,6,7,6,5,4},crateCount=2,wall={2,3,4},
    blue={'.RF.','.WSA.','.B..O.'}},
  {id='narrows',name='The Narrows',description='Two central hexes connect the opposing armies.',
    code=7,rows={5,6,7,8,9,8,9,8,7,6,5},crateCount=3,wall={3,4},
    gaps={[4]={ [3]=true,[5]=true },[5]={ [0]=true,[1]=true,[2]=true,[5]=true,[6]=true,[7]=true },
      [6]={ [3]=true,[5]=true }},
    blue={'..F..','.W..R.','.A...O.','..B..S..'}},
  {id='bridges',name='Twin Bridges',description='Two crossings. Split your army or pick a side.',
    rows={5,6,7,8,9,8,7,6,5},crateCount=4,wall={1,2,6,7},crossings={[1]=true,[2]=true,[6]=true,[7]=true},
    blue={'.BFB.','R....W','.O.A.O.','..S..S..'}},
  {id='wide',name='Wide Front',description='Full armies with room to attack on either flank.',
    rows={5,6,7,8,9,8,9,8,7,6,5},crateCount=5,wall={1,2,3,4,5,6},
    blue={'.BFB.','.WRRW.','O.ASA.O','.SS..SS.'}},
  {id='corners',name='Four Corners',description='Mixed armies converge on two neighboring Fortresses.',
    code=8,rows={7,8,7,8,7,8,7,8,7,8,7},crateCount=4,
    -- Keys are zero-based row numbers and values are the playable columns in those rows.
    footprint={
      [0]={0,1,5,6},{0,1,2,5,6,7},{0,1,5,6},{1,3,4,6},
      {0,1,2,3,4,5,6},{0,2,3,4,5,7},{0,1,2,3,4,5,6},
      {1,3,4,6},{0,1,5,6},{0,1,2,5,6,7},{0,1,5,6},
    },
    wallRing={{4,2},{4,3},{4,4},{5,5},{6,4},{6,3},{6,2},{5,2}},
    formation={
      {'.....BA','........','.......','.A.O....','.......','...F....','.......','.W.S....','.......','........','.....OB'},
      {'BO.....','........','.......','....O.W.','.......','....F...','.......','....S.A.','.......','........','AB.....'},
    }},
}
-- Earlier Narrows matches still replay on the original footprint.
local legacy={id='narrows-legacy',code=3,name='The Narrows',description='Hold the line at a two-hex pass.',
    rows={5,6,7,6,5,2,5,6,7,6,5},crateCount=3,wall={0,1},
    blue={'.BFB.','.R..W.','.O.A.B.','..SS..'}}
boards.byCode={}
local function register(board,code)
  board.code=board.code or code
  board.middle=math.floor(#board.rows/2)
  board.columns=math.max((table.unpack or unpack)(board.rows))
  if board.footprint then
    board.gaps={}
    for r,columns in pairs(board.footprint) do
      local missing={}
      for c=0,board.rows[r+1]-1 do missing[c]=true end
      for _,c in ipairs(columns) do missing[c]=nil end
      board.gaps[r]=missing
    end
    board.footprint=nil
  end
  boards[board.id]=board
  boards.byCode[board.code]=board
end
for code,board in ipairs(boards) do register(board,code) end
register(legacy)
boards.byCode[6]=boards.bridges
return boards
