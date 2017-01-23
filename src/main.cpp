#include <CLCommon/CLCommon.h>
#include <Common/File.h>
#include <Common/Exception.h>
#include <iostream>

int main() {
	const int maxsamples = 50;
	const int maxsize = 40;

	CLCommon::CLCommon clCommon;
	cl::Context ctx = clCommon.context;
	cl::CommandQueue cmds = clCommon.commands;
	cl::Device device = clCommon.device;

	std::string realStr = "float";
	typedef float real;

	size_t gridsize = 4;
	cl::NDRange globalSize(gridsize, gridsize);
	
	//TODO calculate this
	cl::NDRange localSize(4, 4);
	
	std::ofstream f("out.cpp.txt");	

	f << "#size	min	avg	max	times" << std::endl;

	for (int size = 1; size <= maxsize; ++size) {
		std::vector<std::string> sourceStrs = {
			std::string() + "typedef "+realStr+" real;\n",
			std::string() + "#define gridsize " + std::to_string(gridsize) + "\n",
			std::string() + "#define size " + std::to_string(size) + "\n",
			Common::File::read("res/grid-mul.cl"),
		};
		std::vector<std::pair<const char *, size_t>> sources;
		for (const std::string &s : sourceStrs) {
			sources.push_back(std::pair<const char *, size_t>(s.c_str(), s.length()));
		}
		cl::Program program(ctx, sources);

		try {
			program.build({device});// -Werror -cl-fast-relaxed-math");
		} catch (std::exception& err) {	//cl::Error
			throw Common::Exception() 
				<< "failed to build program executable!\n"
				<< program.getBuildInfo<CL_PROGRAM_BUILD_LOG>(device);
		}
		//warnings?
		std::cerr << program.getBuildInfo<CL_PROGRAM_BUILD_LOG>(device) << std::endl;

		size_t vecSize = gridsize * gridsize * size;
		size_t matSize = gridsize * gridsize * size * size;
		cl::Buffer x(ctx, CL_MEM_READ_WRITE, vecSize * sizeof(real));
		cl::Buffer y(ctx, CL_MEM_READ_WRITE, vecSize * sizeof(real));
		cl::Buffer A(ctx, CL_MEM_READ_WRITE, matSize * sizeof(real));
	
		cl::Kernel init(program, "init");
		CLCommon::setArgs(init, y, A, x);
	
		cl::Kernel mul(program, "mul");
		CLCommon::setArgs(mul, y, A, x);
	
		cmds.enqueueNDRangeKernel(init, cl::NDRange(0,0), globalSize, localSize);

		std::vector<double> thistimes(maxsamples);
		for (int tries = 0; tries < maxsamples; ++tries) {
			cl::Event event;
			cmds.enqueueNDRangeKernel(mul, cl::NDRange(0,0), globalSize, localSize, nullptr, &event);
			event.wait();

			cl_ulong start = event.getProfilingInfo<CL_PROFILING_COMMAND_START>();
			cl_ulong end = event.getProfilingInfo<CL_PROFILING_COMMAND_END>();
			double time = (double)(end - start) * 1e-9;
			thistimes[tries] = time;
		}
		
		double avg = 0.;
		double min = std::numeric_limits<double>::infinity();
		double max = -std::numeric_limits<double>::infinity();
		for (double time : thistimes) {
			avg += time;
			min = std::min<double>(min, time);
			max = std::max<double>(max, time);
		}
		avg /= (double)maxsamples;
		
		f << size << "\t" << min << "\t" << avg << "\t" << max;
		for (double time : thistimes) {
			f << "\t" << time;
		}
		f << std::endl;
	}
}
