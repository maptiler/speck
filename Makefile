CFLAGS = -std=c17 -Wall -Wextra -Werror -fPIC `pkg-config --cflags lua` -DPIKCHR_LUA
LDFLAGS = `pkg-config --libs lua` -lm

all: src/pikchr.so

src/pikchr.so: src/pikchr.c
	cc $(CFLAGS) -shared -o src/pikchr.so src/pikchr.c $(LDFLAGS)

install:
	install -D -t /usr/local/lib/lua/5.4/ src/pikchr.so
	install -D -t /usr/local/share/speck src/speck.html src/speck.js src/speck.css src/crossref.yaml src/pikchr.lua
	install -t /usr/local/bin src/speck

clean:
	rm -f src/pikchr.so
