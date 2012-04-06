all: elixir

elixir: src/*
	rm -rf __MAIN__
	elixirc src/*.ex

.PHONY: clean

clean:
	rm -rf __MAIN__

