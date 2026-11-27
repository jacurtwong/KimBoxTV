#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>

#include <memory>

#include "boss_key_channel.h"
#include "native_mpv_host.h"
#include "process_job.h"
#include "render_probe_channel.h"
#include "win32_window.h"
#include "window_fullscreen.h"

class FlutterWindow : public Win32Window {
 public:
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  flutter::DartProject project_;
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
  std::unique_ptr<BossKeyHandler> boss_key_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      boss_key_channel_;
  std::unique_ptr<WindowFullscreen> fullscreen_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      fullscreen_channel_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      process_job_channel_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      render_probe_channel_;
  std::unique_ptr<NativeMpvHost> native_mpv_host_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
