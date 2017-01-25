typedef struct {
	real v[size];
} vectype;

typedef struct {
	real v[size][size];
} mattype;

#define initKernel()	\
	size_t i = get_global_id(0);	\
	size_t j = get_global_id(1);	\
	if (i >= gridsize || j >= gridsize) return;	\
	int index = i + gridsize * j;

kernel void init(
	global vectype* y,
	global mattype* A,
	global vectype* x
) {
	initKernel();
	global vectype *yp = y + index;
	global vectype *xp = x + index;
	global mattype *Ap = A + index;
	for (int a = 0; a < size; ++a) {
		xp->v[a] = a+1;
		yp->v[a] = 0;
		for (int b = 0; b < size; ++b) {
			Ap->v[a][b] = 1 + a + size * b;
		}
	}
}

kernel void mul(
	global vectype* y,
	global const mattype* A,
	global const vectype* x
) {
	initKernel();
	global vectype* yp = y + index;
	global const vectype* xp = x + index;
	global const mattype* Ap = A + index;
	for (int a = 0; a < size; ++a) {
		yp->v[a] = 0;
		for (int b = 0; b < size; ++b) {
			yp->v[a] += Ap->v[a][b] * xp->v[b];
		}
	}
}
