#include "window_fullscreen.h"

#include <flutter/standard_method_codec.h>

#include <variant>

void WindowFullscreen::SetFullScreen(bool value) {
  if (value == fullscreen_ || window_ == nullptr) {
    return;
  }
  if (value) {
    saved_style_ = ::GetWindowLongPtr(window_, GWL_STYLE);
    ::GetWindowRect(window_, &saved_rect_);
    MONITORINFO monitor{};
    monitor.cbSize = sizeof(monitor);
    if (!::GetMonitorInfo(::MonitorFromWindow(window_, MONITOR_DEFAULTTONEAREST),
                          &monitor)) {
      return;
    }
    ::SetWindowLongPtr(window_, GWL_STYLE, saved_style_ & ~WS_OVERLAPPEDWINDOW);
    fullscreen_ = true;
    const RECT& r = monitor.rcMonitor;
    ::SetWindowPos(window_, HWND_TOP, r.left, r.top, r.right - r.left,
                   r.bottom - r.top, SWP_NOOWNERZORDER | SWP_FRAMECHANGED);
  } else {
    fullscreen_ = false;
    ::SetWindowLongPtr(window_, GWL_STYLE, saved_style_);
    const RECT& r = saved_rect_;
    ::SetWindowPos(window_, nullptr, r.left, r.top, r.right - r.left,
                   r.bottom - r.top,
                   SWP_NOZORDER | SWP_NOOWNERZORDER | SWP_NOACTIVATE |
                       SWP_FRAMECHANGED);
  }
}

std::optional<LRESULT> WindowFullscreen::HandleMessage(UINT message,
                                                       WPARAM wparam,
                                                       LPARAM /*lparam*/) {
  if (fullscreen_ && message == WM_NCCALCSIZE && wparam) {
    return 0;
  }
  return std::nullopt;
}

std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
RegisterWindowFullscreenChannel(flutter::BinaryMessenger* messenger,
                                WindowFullscreen* fullscreen) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, "kimbox/window_fullscreen",
          &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler(
      [fullscreen](
          const flutter::MethodCall<flutter::EncodableValue>& call,
          std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
              result) {
        if (call.method_name() == "isFullScreen") {
          result->Success(flutter::EncodableValue(fullscreen->IsFullScreen()));
          return;
        }
        if (call.method_name() != "setFullScreen") {
          result->NotImplemented();
          return;
        }
        const auto* args =
            std::get_if<flutter::EncodableMap>(call.arguments());
        if (args == nullptr) {
          result->Error("bad_args", "需要 {isFullScreen: bool}");
          return;
        }
        auto it = args->find(flutter::EncodableValue("isFullScreen"));
        const bool* value =
            it == args->end() ? nullptr : std::get_if<bool>(&it->second);
        if (value == nullptr) {
          result->Error("bad_args", "isFullScreen 必须是 bool");
          return;
        }
        fullscreen->SetFullScreen(*value);
        result->Success(flutter::EncodableValue(fullscreen->IsFullScreen()));
      });
  return channel;
}
