#ifndef RUNNER_BOSS_KEY_CHANNEL_H_
#define RUNNER_BOSS_KEY_CHANNEL_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <memory>
#include <optional>

class BossKeyHandler {
 public:
  explicit BossKeyHandler(HWND window);
  ~BossKeyHandler();

  bool Register(int modifiers, int vkCode);
  bool Unregister();
  bool IsRegistered() const { return registered_; }

  void SetChannel(
      flutter::MethodChannel<flutter::EncodableValue>* channel) {
    channel_ = channel;
  }

  std::optional<LRESULT> HandleMessage(UINT message,
                                       WPARAM wparam,
                                       LPARAM lparam);

 private:
  static constexpr int kHotkeyId = 0x4B42;  // 'KB'
  HWND window_ = nullptr;
  bool registered_ = false;
  flutter::MethodChannel<flutter::EncodableValue>* channel_ = nullptr;
};

std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
RegisterBossKeyChannel(flutter::BinaryMessenger* messenger,
                       BossKeyHandler* boss_key);

#endif  // RUNNER_BOSS_KEY_CHANNEL_H_
