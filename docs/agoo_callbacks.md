User:

Help me research this thing about the on_open callback in the Agoo server. What's the deal? Can you please help clarify what might be going on, help debug/troubleshoot this?

o3:

Fast-track checklist (try these first)
	1.	Update Agoo – any version ≥ 2.1.1 is required; earlier builds had a bug where writing from #on_open immediately killed the connection.  ￼
	2.	Confirm your Rack handler sets env['rack.upgrade'] to the same object that defines the callback; if the upgrade never happens, on_open is never invoked.  ￼
	3.	Avoid heavy work or long-running I/O inside on_open; return quickly so the event loop can move on.
	4.	If you do push data in on_open, wrap it in Thread.new { … } (or enqueue it) so the callback finishes immediately.
	5.	Turn on Agoo’s push, connect, and request log flags—watch the console while you connect; you should see --- on_open.  ￼

⸻

How on_open is supposed to fire

When a client asks to upgrade (GET /upgrade with Upgrade: websocket), your Rack handler:

env['rack.upgrade'] = MyPushHandler   # or an *instance*
[200, {}, []]

Agoo then calls, in order:
	1.	perform the TCP→WebSocket/SSE handshake
	2.	invoke handler.on_open(client)
	3.	hand further frames to on_message, etc.

All five callbacks (on_open, on_message, on_close, on_drained, on_shutdown) are optional; you only need the ones you care about.  ￼

⸻

Common trip-wires & fixes

Symptom	Root cause	Fix
on_open never called	Handler object never reaches server (forgot to set env['rack.upgrade'], typo in path, or you passed a class but wrote an instance method)	Double-check the Rack block; if you pass a class, define self.on_open; if you pass an instance, define def on_open.
Connection closes right after opening	You call client.write inside on_open on Agoo < 2.1.1	Upgrade; bug was patched.  ￼
Works in dev, stalls under load	Heavy work inside on_open blocks reactor	Off-load heavy work to a new thread/fiber; keep callback O(μs).
Random “broken pipe” after TLS	Using Ruby 3.2 on macOS with Agoo < 2.15.4	Upgrade; libssl symbol fix.  ￼


⸻

Debugging workflow
	1.	Minimal repro – start with the clock example in the docs and watch for --- on_open. If that fires, the issue is in your handler.
	2.	Verbose logs –

Agoo::Log.configure(states: {connect: true, push: true, request: true})

Every new socket should print connect → on_open.

	3.	Unit test it – use WebSocket::Client::Simple in Ruby or plain JS in Node:

ws = WebSocket.new('ws://localhost:6464/upgrade')
ws.on(:open) { puts 'client connected' }

If client open fires but server on_open does not, the handshake terminated early—look for TLS or proxy interference.

⸻

If you must publish inside on_open

Publishing immediately after the handshake is okay now (post-2.1.1), but you still risk losing the first frame if the browser hasn’t finished its JS sock.onopen = … wiring. Better pattern:

def on_open(c)
  c.write(JSON.dump(type: 'welcome', t: Time.now.to_i))
  # spin off any heavy init work
  Thread.new { expensive_setup(c) }
end

The initial write is tiny, guaranteed to flush; anything bigger waits.

⸻

Still stuck?

Drop a snippet like:

class Chat
  def call(env)
    env['rack.upgrade'] = self
    [200, {}, []]
  end
  def on_open(c)  # <— never fires?
    puts :open
  end
end

…along with the console log lines you see. We can inspect the exact handshake and nail the culprit.

⸻

(Anything else in your stack that feels “mysterious”? I’m happy to keep digging once you’ve run those first diagnostics.)