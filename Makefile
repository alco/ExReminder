all: __MAIN__/Event __MAIN__/EventServer

.PHONY: clean

clean:
	rm -rf __MAIN__

__MAIN__/Event: src/event.ex
	rm -rf __MAIN__/Event __MAIN__/Event.beam
	elixirc src/event.ex

__MAIN__/EventServer: src/event_server.ex
	rm -rf __MAIN__/EventServer __MAIN__/EventServer.beam
	elixirc src/event_server.ex

