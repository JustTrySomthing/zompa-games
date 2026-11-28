-- Board identifiers and wire codes are stable across saved and online matches.
local boards={
  {id='classic',name='Classic',description='Full armies on the original battlefield.',
    rows={3,4,5,6,7,6,7,6,5,4,3},crateCount=3},
  {id='skirmish',name='Skirmish',description='Six troops per side for a quicker match.',
    rows={4,5,6,7,6,5,4},crateCount=2,wall={2,3,4},
    blue={'.RF.','.WSA.','.B..O.'}},
  {id='narrows',name='The Narrows',description='Hold the line at a two-hex pass.',
    rows={5,6,7,6,5,2,5,6,7,6,5},crateCount=3,wall={0,1},
    blue={'.BFB.','.R..W.','.O.A.B.','..SS..'}},
  {id='bridges',name='Twin Bridges',description='Two crossings. Split your army or pick a side.',
    rows={5,6,7,8,9,8,7,6,5},crateCount=4,wall={1,2,6,7},crossings={[1]=true,[2]=true,[6]=true,[7]=true},
    blue={'.BFB.','R....W','.O.A.O.','..S..S..'}},
  {id='wide',name='Wide Front',description='Full armies with room to attack on either flank.',
    rows={5,6,7,8,9,8,9,8,7,6,5},crateCount=5,wall={1,2,3,4,5,6},
    blue={'.BFB.','.WRRW.','O.ASA.O','.SS..SS.'}},
}
for code,board in ipairs(boards) do
  board.code=code
  board.middle=math.floor(#board.rows/2)
  board.columns=math.max((table.unpack or unpack)(board.rows))
  boards[board.id]=board
end
return boards
