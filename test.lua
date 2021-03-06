#!/usr/bin/env luajit
local osname = require'ffi'.os:lower()

local distdir = ({windows='msvc'})[osname] or osname

local function exec(cmd)
	if osname == 'windows' then cmd = cmd:gsub('/', '\\') end
	print(cmd)
	assert(os.execute(cmd))
end

local maxsize = 40
local maxsamples = 200

--[[
print'executing c++'
exec'lua -lmake'
exec('dist/'..distdir..'/release/MatMulKernelTest float '..maxsize..' '..maxsamples)
--exec('dist/'..distdir..'/release/MatMulKernelTest double '..maxsize..' '..maxsamples)
--]]
--[[
print'executing lua float'
exec('luajit grid-mul-obj.lua float '..maxsize..' '..maxsamples)
--]]
--[[
print'executing lua double'
exec('luajit grid-mul-obj.lua double '..maxsize..' '..maxsamples)
--]]

print'plotting results...'
for _,prec in ipairs{'float', 'double'} do
	for _,info in ipairs{{min=2}, {avg=3}, {max=4}} do
		local field, index = next(info)
		require 'gnuplot'{
			output = 'comparison-'..field..'-'..prec..'.png',
			title = field..' time to perform using '..prec..' precision',
			xlabel = 'matrix/vector multiply size',
			ylabel = 'seconds',
			xtics = 1,
			--log = 'y',
			style = 'data linespoints',
			{datafile='out.linux.cpp.'..prec..'.txt', using='1:'..index, title='Ubuntu C++'},
			{datafile='out.linux.lua.obj.'..prec..'.txt', using='1:'..index, title='Ubuntu Lua cl.obj'},
			{datafile='out.msvc.cpp.'..prec..'.txt', using='1:'..index, title='Windows MSVC C++'},
			{datafile='out.msvc.lua.obj.'..prec..'.txt', using='1:'..index, title='Windows Lua cl.obj'},
		}
	end
end
