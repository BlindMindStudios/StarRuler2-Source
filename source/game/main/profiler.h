
namespace profiler {

	//Returns a value to pass to a call to 'profileEnd'
	double profileStart();

	//Prints out the time elapsed since 'startTime' as returned by 'profileStart'
	void profileEnd(double startTime, const char* section);

#define profile( x, name ) { double _t = profiler::profileStart(); x; profiler::profileEnd(_t, name); }

};