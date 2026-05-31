CFLAGS = -std=c17 -Wall -Wextra -Werror -fPIC `pkg-config --cflags lua` -DPIKCHR_LUA
LDFLAGS = `pkg-config --libs lua` -lm

all: pikchr.so

pikchr.so: pikchr.c
	cc $(CFLAGS) -shared -o $@ $^ $(LDFLAGS)

clean:
	rm -f pikchr.so
