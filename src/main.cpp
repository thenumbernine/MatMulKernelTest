#include <CLCommon/CLCommon.h>
#include <Common/File.h>
#include <Common/Exception.h>
#include <iostream>
#include <algorithm>
#include <vector>
#include <string>

#if PLATFORM_LINUX
static std::string platform = "linux";
#elif PLATFORM_MSVC
static std::string platform = "msvc";
#else
#error unknown platform
#endif

template<typename real> struct RealStr;
template<> struct RealStr<float> { static std::string getStr() { return "float"; } };
template<> struct RealStr<double> { static std::string getStr() { return "double"; } };

template<typename real>
void test(CLCommon::CLCommon& clCommon, int maxsize, int maxsamples) {
	std::string realStr = RealStr<real>::getStr();

	std::cerr << "using real " << realStr << std::endl;
	std::cerr << "sizeof real " << sizeof(real) << std::endl;
	std::cerr << "running until size=" << maxsize << std::endl;
	std::cerr << "using " << maxsamples << " samples" << std::endl;

	cl::Context ctx = clCommon.context;
	cl::CommandQueue cmds = clCommon.commands;
	cl::Device device = clCommon.device;

	size_t gridsize = 256;
	cl::NDRange globalSize(gridsize, gridsize);
	
	//TODO calculate this
	cl::NDRange localSize(16, 16);
	
	std::ofstream f(std::string() + "out." + platform + ".cpp." + realStr + ".txt");	
	f << "#size	min	avg	max	times" << std::endl;

	for (int size = 1; size <= maxsize; ++size) {
		std::vector<std::string> sourceStrs = {
			std::string() + "typedef "+realStr+" real;\n",
			std::string() + "#define gridsize " + std::to_string(gridsize) + "\n",
			std::string() + "#define size " + std::to_string(size) + "\n",
			Common::File::read("res/grid-mul.cl"),
		};
		std::vector<std::string> sources;
		for (const std::string &s : sourceStrs) {
			sources.push_back(s);
		}
		cl::Program program(ctx, sources);

		try {
			program.build({device});// -Werror -cl-fast-relaxed-math");
		} catch (std::exception& err) {	//cl::Error
			throw Common::Exception() 
				<< "failed to build program executable!\n"
				<< program.getBuildInfo<CL_PROGRAM_BUILD_LOG>(device);
		}

/*
Print any warnings.
This is giving me results that the Lua version is not:
But then again, in the Lua version, I'm throwing the log away upon success...

Compilation started
Compilation done
Linking started
Linking done
Device build started
Device build done
Kernel <init> was not vectorized
Kernel <mul> was not vectorized
Done.

*/
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

bool checkHasFP64(const cl::Device& device) {
	std::vector<std::string> extensions = CLCommon::getExtensions(device);
	return std::find(extensions.begin(), extensions.end(), "cl_khr_fp64") != extensions.end();
}

int main(int argc, char** argv) {
	std::string realStr = (argc > 1) ? argv[1] : "float";
	bool use64 = realStr != "float";

	CLCommon::CLCommon clCommon(
		/*useGPU=*/true,
		/*verbose=*/true,
		/*pickDevice=*/[&](const std::vector<cl::Device>& devices_) -> std::vector<cl::Device>::const_iterator {
			std::vector<cl::Device> devices = devices_;
			std::sort(
				devices.begin(),
				devices.end(),
				[&](const cl::Device& a, const cl::Device& b) -> bool {
					return checkHasFP64(a) > checkHasFP64(b);
				});

			cl::Device best = devices[0];
			//return std::find<std::vector<cl::Device>::const_iterator, cl::Device>(devices_.begin(), devices_.end(), best);
			for (std::vector<cl::Device>::const_iterator iter = devices_.begin(); iter != devices_.end(); ++iter) {
				if ((*iter)() == best()) return iter;
			}
			throw Common::Exception() << "couldn't find a device";
		});
	
	use64 &= checkHasFP64(clCommon.device);
	
	int maxsize = 40;
	if (argc > 2) maxsize = atoi(argv[2]);
	int maxsamples = 50;
	if (argc > 3) maxsamples = atoi(argv[3]);

	if (use64) {
		test<double>(clCommon, maxsize, maxsamples);
	} else {
		test<float>(clCommon, maxsize, maxsamples);
	}
}
