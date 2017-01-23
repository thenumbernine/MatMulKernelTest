#!/usr/bin/env lua
local function exec(cmd)
	print(cmd)
	assert(os.execute(cmd))
end
--[[
print'executing lua'
exec'./grid-mul.lua'
print'executing c++'
exec'lua -lmake'
exec'dist/linux/release/MatMulKernelTest'
--]]
print'plotting results...'
require 'gnuplot'{
	output = 'comparison.png',
	xtics = 1,
	style = 'data linespoints',
	{datafile='out.cpp.txt', using='1:2', title='C++'},
	{datafile='out.lua.txt', using='1:2', title='Lua'},
}
