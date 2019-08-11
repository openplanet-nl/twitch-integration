# Twitch Chat integration
Scripts to integrate Twitch Chat into Openplanet scripts.

This repository also includes [an example plugin](https://openplanet.nl/files/23) for displaying the Twitch Chat in-game in the overlay.

# Usage
Put the scripts somewhere in `C:\Users\Username\Openplanet4\Scripts\` so that you can `#include` them. Here's a quick example:

```angelscript
#include "TwitchChat.as"

class ChatCallbacks : Twitch::ICallbacks
{
	void OnMessage(IRC::Message@ msg)
	{
		// ...
	}

	void OnUserNotice(IRC::Message@ msg)
	{
		// ...
	}
}

void Main()
{
	print("Connecting to Twitch chat...");

	auto callbacks = ChatCallbacks();
	if (!Twitch::Connect(callbacks)) {
		return;
	}

	print("Connected to Twitch chat!");

	Twitch::Login(
		Setting_TwitchToken,
		Setting_TwitchNickname,
		Setting_TwitchChannel
	);

	while (true) {
		Twitch::Update();
		yield();
	}
}
```
