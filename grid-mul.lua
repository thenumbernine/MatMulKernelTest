#!/usr/bin/env luajit
--[[
I seem to be getting some funny performance with my HD520 with large multiply kernels across a grid
I want to verify that it is proportional to operations
--]]
require 'ext'
local ffi = require 'ffi'
local cl = require 'ffi.OpenCL'
local CLEvent = require 'cl.event'
local env = require 'cl.obj.env'{size={256,256}, queue={properties=cl.CL_QUEUE_PROFILING_ENABLE}}
local template = require 'template'

local maxsize = 50
local maxsamples = 40
local sizes = range(maxsize)
local times = sizes:map(function(size)
	local vecType = 'vec_'..size..'_t'
	local matType = 'mat_'..size..'_'..size..'_t'
	local typeCode = template([[
typedef struct {
	real v[<?=size?>];
} <?=vecType?>;

typedef struct {
	real v[<?=size?>][<?=size?>];
} <?=matType?>;
]], {
	size = size,
	vecType = vecType,
	matType = matType,
})
	ffi.cdef(typeCode)

	local x = env:buffer{name='x', type=vecType}
	local y = env:buffer{name='y', type=vecType}
	local A = env:buffer{name='A', type=matType}
	-- initialize
	env:kernel{
		argsOut = {x, y, A},
		header = typeCode,
		body = template([[
	global <?=vecType?> *yp = y + index;
	global <?=vecType?> *xp = x + index;
	global <?=matType?> *Ap = A + index;
	for (int a = 0; a < <?=size?>; ++a) {
		xp->v[a] = a+1;
		yp->v[a] = 0;
		for (int b = 0; b < <?=size?>; ++b) {
			Ap->v[a][b] = 1 + a + <?=size?> * b;
		}
	}
]], 	{
			size = size,
			vecType = vecType,
			matType = matType,
		}),
	}()
	
	-- perform operation
	local event = CLEvent()
	mulKernel = env:kernel{
		argsOut = {y},
		argsIn = {A, x},
		event = event,
		header = typeCode,
		body = template([[
	global <?=vecType?>* yp = y + index;
	global const <?=vecType?>* xp = x + index;
	global const <?=matType?>* Ap = A + index;
	for (int a = 0; a < <?=size?>; ++a) {
		yp->v[a] = 0.;
		for (int b = 0; b < <?=size?>; ++b) {
			yp->v[a] += Ap->v[a][b] * xp->v[b];
		}
	}
]], 	{
			size = size,
			vecType = vecType,
			matType = matType,
		}),
	}
	local times = table()
	for try=1,maxsamples do
		mulKernel()
		mulKernel.event:wait()
		local start = event:getProfilingInfo'CL_PROFILING_COMMAND_START'
		local finish = event:getProfilingInfo'CL_PROFILING_COMMAND_END'
		local thisTime = tonumber(finish - start) * 1e-9
		times:insert(thisTime)
	end
	return times
end)

-- used for scatterplot
local allSizes = table()
local allTimes = table()
for i,size in ipairs(sizes) do
	allTimes:append(times[i])
	allSizes:append(range(#times[i]):map(function() return size end))	-- table{size}:rep(#times[i])
end

local avgs = times:map(function(time) return time:sum()/#time end)
local mins = times:map(function(time) return (time:inf()) end)
local maxs = times:map(function(time) return (time:sup()) end)

print('#size	min	avg	max	times')
for i,size in ipairs(sizes) do
	local time = times[i]
	print(size, mins[i], avgs[i], maxs[i], time:unpack())
end

require 'gnuplot'{
	output = 'out.lua.png',
	xlabel = 'size of vector/matrix multiplication within each grid cell',
	ylabel = 'seconds',
	xtics = 1,
	title = 'number of samples per size = '..maxsamples,
	data = {
		allSizes, allTimes,
		sizes,
		mins, 
		avgs, 
		maxs, 
	},
	{using='1:2', title='time', with='points'},
	{using='3:4', title='min', with='lines'},
	{using='3:5', title='avg', with='lines'},
	{using='3:6', title='max', with='lines'},
}
