#!/usr/bin/env luajit
--[[
I seem to be getting some funny performance with my HD520 with large multiply kernels across a grid
I want to verify that it is proportional to operations
--]]
require 'ext'
local ffi = require 'ffi'

local platform, device, ctx, queue = require 'cl'{
	
}

error'here'

local cl = require 'ffi.OpenCL'
local CLEvent = require 'cl.event'
local env = require 'cl.obj.env'{size={256,256}, queue={properties=cl.CL_QUEUE_PROFILING_ENABLE}}
local template = require 'template'

local maxsamples = 50
local maxsize = 40

local sizes = range(maxsize)
-- running backwards vs forwards makes no difference so allocation order isn't affecting the strange performance curve in Lua
--local sizes = range(maxsize,1,-1)

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
	local event = CLEvent()
	
-- compiling two vs one program makes no difference.  why would it anyways?
--[=[ using two separate programs
	-- initialize
	local init = env:kernel{
		argsOut = {y, A, x},
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
	}
	init()
	
	-- perform operation
	mul = env:kernel{
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
	mul:compile()
--]=]
-- [=[ using one program
	local program = env:program{
		code = 
--[==[ using the same code as the C++ demo ... but this redefines a lot in env.code
			table{
				'typedef '..env.real..' real;',
				'#define gridsize '..env.base.size.x,
				'#define size '..size,
				assert(file['res/grid-mul.cl']),
			}:concat'\n',
--]==]
-- [==[ using env's code
		template([[
<?=typeCode?>

kernel void init(
	global <?=vecType?>* y,
	global <?=matType?>* A,
	global <?=vecType?>* x
) {
	initKernel();
	global <?=vecType?>* yp = y + index;
	global <?=matType?>* Ap = A + index;
	global <?=vecType?>* xp = x + index;
	for (int a = 0; a < <?=size?>; ++a) {
		xp->v[a] = a+1;
		yp->v[a] = 0;
		for (int b = 0; b < <?=size?>; ++b) {
			Ap->v[a][b] = 1 + a + <?=size?> * b;
		}
	}
}

kernel void mul(
	global <?=vecType?>* y,
	global const <?=matType?>* A,
	global const <?=vecType?>* x
) {
	initKernel();
	global <?=vecType?>* yp = y + index;
	global const <?=matType?>* Ap = A + index;
	global const <?=vecType?>* xp = x + index;
	for (int a = 0; a < <?=size?>; ++a) {
		yp->v[a] = 0.;
		for (int b = 0; b < <?=size?>; ++b) {
			yp->v[a] += Ap->v[a][b] * xp->v[b];
		}
	}
}
]],		{
			size = size,
			vecType = vecType,
			matType = matType,
			typeCode = typeCode,
		}),
--]==]
	}

	local init = program:kernel{
		name = 'init',
		argsOut = {y, A, x},
	}

	local mul = program:kernel{
		name = 'mul',
		argsOut = {y},
		argsIn = {A, x},
		event = event,
	}

	program:compile()
--]=]

	local times = table()
	for try=1,maxsamples do
		mul()
		event:wait()
		local start = event:getProfilingInfo'CL_PROFILING_COMMAND_START'
		local finish = event:getProfilingInfo'CL_PROFILING_COMMAND_END'
		local thisTime = tonumber(finish - start) * 1e-9
		times:insert(thisTime)
	end

	x.obj:release()	-- will the gc know not to release after this call?
	y.obj:release()
	A.obj:release()
--[=[ using two separate programs	
	init.obj:release()
	init.program.obj:release()
	mul.obj:release()
	mul.program.obj:release()
--]=]
-- [=[ using one program
	program.obj:release()
	init.obj:release()
	mul.obj:release()
--]=]
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

local f = assert(io.open('out.lua.obj.txt', 'w'))
f:write'#size	min	avg	max	times\n'
f:flush()
for i,size in ipairs(sizes) do
	local time = times[i]
	f:write(size,'\t',mins[i],'\t',avgs[i],'\t',maxs[i],'\t',time:concat'\t','\n')
	f:flush()
end
f:close()

require 'gnuplot'{
	output = 'out.lua.obj.png',
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
