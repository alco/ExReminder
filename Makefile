all: __MAIN__/Event __MAIN__/EventServer

__MAIN__/Event: src/event.ex
	rm -rf __MAIN__/Event
	rm __MAIN__/Event.beam
	elixirc src/event.ex

__MAIN__/EventServer: src/event_server.ex
	rm -rf __MAIN__/EventServer
	rm __MAIN__/EventServer.beam
	elixirc src/event_server.ex

