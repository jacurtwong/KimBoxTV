#ifndef RUNNER_WINDOW_FULLSCREEN_H_
#define RUNNER_WINDOW_FULLSCREEN_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <memory>
#include <optional>

class WindowFullscreen {
 public:
  explicit WindowFullscreen(HWND window) : window_(window) {}

  void SetFullScreen(bool value);
  bool IsFullScreen() const { return fullscreen_; }

  std::optional<LRESULT> HandleMessage(UINT message,
                                       WPARAM wparam,
                                       LPARAM lparam);

 private:
  HWND window_ = nullptr;
  bool fullscreen_ = false;
  LONG_PTR saved_style_ = 0;
  RECT saved_rect_{};
};

std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
RegisterWindowFullscreenChannel(flutter::BinaryMessenger* messenger,
                                WindowFullscreen* fullscreen);

#endif  // RUNNER_WINDOW_FULLSCREEN_H_
