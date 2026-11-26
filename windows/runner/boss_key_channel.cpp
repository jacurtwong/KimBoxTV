#include "boss_key_channel.h"

#include <flutter/standard_method_codec.h>

BossKeyHandler::BossKeyHandler(HWND window) : window_(window) {}

BossKeyHandler::~BossKeyHandler() {
  Unregister();
}

bool BossKeyHandler::Register(int modifiers, int vkCode) {
  Unregister();
  if (window_ == nullptr) return false;

  // MOD_NOREPEAT (0x4000) prevents repeated WM_HOTKEY events when key is held.
  UINT fsModifiers = static_cast<UINT>(modifiers) | 0x4000;
  BOOL success = ::RegisterHotKey(window_, kHotkeyId, fsModifiers,
                                  static_cast<UINT>(vkCode));
  if (!success) {
    success = ::RegisterHotKey(window_, kHotkeyId, static_cast<UINT>(modifiers),
                               static_cast<UINT>(vkCode));
  }
  registered_ = (success != 0);
  return registered_;
}

bool BossKeyHandler::Unregister() {
  if (registered_ && window_ != nullptr) {
    ::UnregisterHotKey(window_, kHotkeyId);
    registered_ = false;
  }
  return true;
}

std::optional<LRESULT> BossKeyHandler::HandleMessage(UINT message,
                                                     WPARAM wparam,
                                                     LPARAM /*lparam*/) {
  if (message == WM_HOTKEY && static_cast<int>(wparam) == kHotkeyId) {
    if (channel_ != nullptr) {
      channel_->InvokeMethod("onBossKeyPressed", nullptr);
    }
    return 0;
  }
  return std::nullopt;
}

std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
RegisterBossKeyChannel(flutter::BinaryMessenger* messenger,
                       BossKeyHandler* boss_key) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, "kimbox/boss_key",
          &flutter::StandardMethodCodec::GetInstance());
  boss_key->SetChannel(channel.get());
  channel->SetMethodCallHandler(
      [boss_key](
          const flutter::MethodCall<flutter::EncodableValue>& call,
          std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
              result) {
        if (call.method_name() == "register") {
          const auto* args =
              std::get_if<flutter::EncodableMap>(call.arguments());
          if (args == nullptr) {
            result->Error("bad_args", "需要 {modifiers: int, vkCode: int}");
            return;
          }
          auto itMod = args->find(flutter::EncodableValue("modifiers"));
          auto itVk = args->find(flutter::EncodableValue("vkCode"));
          if (itMod == args->end() || itVk == args->end()) {
            result->Error("bad_args", "缺少 modifiers 或 vkCode");
            return;
          }
          int modifiers = 0;
          if (std::holds_alternative<int32_t>(itMod->second)) {
            modifiers = std::get<int32_t>(itMod->second);
          } else if (std::holds_alternative<int64_t>(itMod->second)) {
            modifiers = static_cast<int>(std::get<int64_t>(itMod->second));
          }
          int vkCode = 0;
          if (std::holds_alternative<int32_t>(itVk->second)) {
            vkCode = std::get<int32_t>(itVk->second);
          } else if (std::holds_alternative<int64_t>(itVk->second)) {
            vkCode = static_cast<int>(std::get<int64_t>(itVk->second));
          }
          bool ok = boss_key->Register(modifiers, vkCode);
          result->Success(flutter::EncodableValue(ok));
          return;
        }
        if (call.method_name() == "unregister") {
          bool ok = boss_key->Unregister();
          result->Success(flutter::EncodableValue(ok));
          return;
        }
        if (call.method_name() == "isRegistered") {
          result->Success(flutter::EncodableValue(boss_key->IsRegistered()));
          return;
        }
        result->NotImplemented();
      });
  return channel;
}
