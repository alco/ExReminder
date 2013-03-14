all: elixir

elixir: src/*
	elixirc src/*.ex

.PHONY: clean

clean:
	rm *.beam

