CFLAGS = -Iinc
LDFLAGS = -lm

all: triangle_test

triangle_test:
	$(CC) $(CFLAGS) src/triangle.c test/test_triangle.c $(LDFLAGS) -o $@

test: triangle_test
	./triangle_test

clean:
	rm -f triangle_test
