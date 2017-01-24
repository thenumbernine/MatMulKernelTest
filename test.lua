#!/usr/bin/env lua
local function exec(cmd)
	print(cmd)
	assert(os.execute(cmd))
end

--[[
print'executing lua float'
exec'./grid-mul-obj.lua float'
print'executing lua double'
exec'./grid-mul-obj.lua double'
--]]
--[[
print'executing c++'
exec'lua -lmake'
exec'dist/linux/release/MatMulKernelTest float'
exec'dist/linux/release/MatMulKernelTest double'
--]]

print'plotting results...'
require 'gnuplot'{
	output = 'comparison.png',
	xtics = 1,
	style = 'data linespoints',
	{datafile='out.cpp.float.txt', using='1:2', title='C++ float'},
	{datafile='out.cpp.double.txt', using='1:2', title='C++ double'},
	{datafile='out.lua.obj.float.txt', using='1:2', title='Lua cl.obj float'},
	{datafile='out.lua.obj.double.txt', using='1:2', title='Lua cl.obj double'},
}
