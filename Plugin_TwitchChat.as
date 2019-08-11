#name "Twitch Chat"
#author "Miss"
#category "Streaming"

#include "TwitchChat.as"

[Setting name="Twitch OAuth Token" password]
string Setting_TwitchToken;

[Setting name="Twitch Nickname" description="Lowercase."]
string Setting_TwitchNickname;

[Setting name="Twitch Channel" description="Lowercase and including the # sign, for example: #missterious"]
string Setting_TwitchChannel;

[Setting name="Enable chat overlay"]
bool Setting_ChatOverlay = true;

[Setting name="Enable chat overlay message timer"]
bool Setting_ChatOverlayMessageTimer = true;

[Setting name="Message time"]
int Setting_ChatMessageTime = 10000;

[Setting name="Message bits threshold"]
int Setting_ChatMessageBitsThreshold = 100;

[Setting name="Message bits time"]
int Setting_ChatMessageBitsTime = 25000;

[Setting name="Message subscription time"]
int Setting_ChatMessageSubscriptionTime = 30000;

[Setting name="Enable !map command"]
bool Setting_MapCommand = true;

[Setting name="Enable !server command"]
bool Setting_ServerCommand = true;

[Setting name="Enable !join command"]
bool Setting_JoinCommand = true;

CTrackMania@ g_app;

class ChatMessage
{
	uint64 m_startTime;
	uint64 m_ttl;

	string m_username;
	string m_text;
	vec4 m_color;
	vec4 m_textColor = vec4(1, 1, 1, 1);

	int m_bits;

	uint64 get_Lifetime()
	{
		return Time::Now - m_startTime;
	}

	int64 get_TimeLeft()
	{
		return int64(m_ttl) - int64(Time::Now - m_startTime);
	}

	float get_TimeFactor()
	{
		return Math::Clamp(float(Time::Now - m_startTime) / float(m_ttl), 0.0f, 1.0f);
	}
}

array<ChatMessage@> g_chatMessages;

CGameCtnChallenge@ GetCurrentMap()
{
#if MP41
	return g_app.RootMap;
#else
	return g_app.Challenge;
#endif
}

string StripFormatCodes(string s)
{
	return Regex::Replace(s, "\\$([0-9a-fA-F]{1,3}|[iIoOnNmMwWsSzZtTgG<>]|[lLhHpP](\\[[^\\]]+\\])?)", "");
}

class ChatCallbacks : Twitch::ICallbacks
{
	void HandleCommand(ChatMessage@ msg)
	{
		if (msg.m_text == "!map" && Setting_MapCommand) {
			auto currentMap = GetCurrentMap();
			if (currentMap !is null) {
				Twitch::SendMessage("The current map is: " + StripFormatCodes(currentMap.MapName) + " by " + StripFormatCodes(currentMap.AuthorNickName));
			} else {
				Twitch::SendMessage("Not currently playing on a map.");
			}

		} else if (msg.m_text == "!server" && Setting_ServerCommand) {
			auto serverInfo = cast<CGameCtnNetServerInfo>(g_app.Network.ServerInfo);
			if (serverInfo.ServerLogin != "") {
				int numPlayers = g_app.ChatManagerScript.CurrentServerPlayerCount - 1;
				int maxPlayers = g_app.ChatManagerScript.CurrentServerPlayerCountMax;

				Twitch::SendMessage("Currently playing on \"" + StripFormatCodes(serverInfo.ServerName) + "\" (" + (numPlayers - 1) + " / " + maxPlayers + ", use !join to get the join link)");
			} else {
				Twitch::SendMessage("Not currently playing on a server.");
			}

		} else if (msg.m_text == "!join" && Setting_JoinCommand) {
			auto serverInfo = cast<CGameCtnNetServerInfo>(g_app.Network.ServerInfo);
			if (serverInfo.ServerLogin != "") {
				auto title = g_app.LoadedManiaTitle;
				string serverLink = "maniaplanet://#qjoin=" + serverInfo.ServerLogin + "@" + title.IdName;
				Twitch::SendMessage("Join link: " + serverLink);
			} else {
				Twitch::SendMessage("Not currently playing on a server.");
			}
		}
	}

	void OnMessage(IRC::Message@ msg)
	{
		auto newMessage = ChatMessage();
		newMessage.m_startTime = Time::Now;
		newMessage.m_ttl = Setting_ChatMessageTime;

		newMessage.m_text = msg.m_params[1];

		newMessage.m_username = msg.m_prefix.m_origin;
		msg.m_tags.Get("display-name", newMessage.m_username);

		string color;
		msg.m_tags.Get("color", color);
		newMessage.m_color = Text::ParseHexColor(color);

		string valueBits;
		if (msg.m_tags.Get("bits", valueBits)) {
			print("Bits donated: " + valueBits);
			newMessage.m_bits = Text::ParseInt(valueBits);

			if (newMessage.m_bits > Setting_ChatMessageBitsThreshold) {
				newMessage.m_ttl = Setting_ChatMessageBitsTime;
				newMessage.m_textColor = vec4(1, 1, 0, 1);
			}
		}

		if (newMessage.m_text.StartsWith("!")) {
			HandleCommand(newMessage);
		}

		g_chatMessages.InsertLast(newMessage);

		print("Twitch chat: " + newMessage.m_username + ": " + newMessage.m_text);
	}

	void OnUserNotice(IRC::Message@ msg)
	{
		string noticeType;
		if (!msg.m_tags.Get("msg-id", noticeType)) {
			return;
		}

		if (noticeType == "sub" || noticeType == "resub" || noticeType == "subgift" || noticeType == "anonsubgift") {
			auto newMessage = ChatMessage();
			newMessage.m_startTime = Time::Now;
			newMessage.m_ttl = Setting_ChatMessageSubscriptionTime;

			msg.m_tags.Get("message", newMessage.m_text);
			if (newMessage.m_text == "") {
				newMessage.m_text = "subscribed!";
			}

			msg.m_tags.Get("display-name", newMessage.m_username);

			string color;
			msg.m_tags.Get("color", color);
			newMessage.m_color = Text::ParseHexColor(color);
			if (newMessage.m_color.w == 0.0f) {
				newMessage.m_color.w = 1.0f;
			}
			newMessage.m_textColor = vec4(1, 0.3f, 1, 1);

			g_chatMessages.InsertLast(newMessage);

			print("New Twitch subscription from " + newMessage.m_username + "!");
		}
	}
}

ChatCallbacks@ g_chatCallbacks;

void Main()
{
	@g_app = cast<CTrackMania>(GetApp());

	if (Setting_TwitchToken == "") {
		print("No Twitch token set. Set one in the settings and reload scripts!");
		return;
	}

	if (Setting_TwitchNickname == "") {
		print("No Twitch nickname set. Set one in the settings and reload scripts!");
		return;
	}

	if (Setting_TwitchChannel == "") {
		print("No Twitch channel set. Set one in the settings and reload scripts!");
		return;
	}

	@g_chatCallbacks = ChatCallbacks();

	print("Connecting to Twitch chat...");

	if (!Twitch::Connect(g_chatCallbacks)) {
		return;
	}

	print("Connected to Twitch chat!");

	Twitch::Login(Setting_TwitchToken, Setting_TwitchNickname, Setting_TwitchChannel);

	while (true) {
		for (int i = int(g_chatMessages.Length) - 1; i >= 0; i--) {
			auto msg = g_chatMessages[i];
			if (msg.TimeLeft <= 0) {
				g_chatMessages.RemoveAt(i);
			}
		}

		Twitch::Update();
		yield();
	}
}

void Render()
{
	if (!Setting_ChatOverlay) {
		return;
	}

	int screenWidth = Draw::GetWidth();
	int screenHeight = Draw::GetHeight();

	int width = 400;
	int height = 200;

	int x = screenWidth / 2 - width / 2;
	int y = 200;

	const int boxPadding = 4;
	const int linePadding = 4;

	for (uint i = 0; i < g_chatMessages.Length; i++) {
		auto msg = g_chatMessages[i];

		vec4 textColor = msg.m_textColor;
		vec4 fillColor = msg.m_color;
		fillColor.w = 0.1f;

		vec2 textSizeUsername = Draw::MeasureString(msg.m_username);

		float maxMessageWidth = width - boxPadding * 3 - textSizeUsername.x;
		vec2 textSizeMessage = Draw::MeasureString(msg.m_text, null, 0.0f, maxMessageWidth);

		Draw::FillRect(vec4(x, y, width, textSizeMessage.y + boxPadding * 2), vec4(0, 0, 0, 0.9f), 4.0f);

		if (Setting_ChatOverlayMessageTimer && msg.TimeFactor < 0.9f) {
			Draw::FillRect(vec4(x, y, width * easeCubic(1.0f - msg.TimeFactor), textSizeMessage.y + boxPadding * 2), fillColor, 4.0f);
		}

		Draw::DrawString(vec2(x + boxPadding, y + boxPadding), msg.m_color, msg.m_username);
		Draw::DrawString(vec2(x + boxPadding + textSizeUsername.x + boxPadding, y + boxPadding), textColor, msg.m_text, null, 0.0f, maxMessageWidth);

		y += int(textSizeMessage.y) + boxPadding * 2 + linePadding;
	}
}

float easeCubic(float x)
{
	if ((x /= 0.5) < 1) return 0.5 * x * x * x;
	return 0.5 * ((x -= 2) * x * x + 2);
}
